import Foundation
import Darwin

// Samples an existing process, without injecting events or requiring root.
// Kernel CPU counters are nanoseconds; memory counters are bytes.
struct Sample: Codable {
    let elapsedSeconds: Double
    let cpuSeconds: Double
    let residentBytes: UInt64
    let footprintBytes: UInt64
    let packageIdleWakeups: UInt64
    let interruptWakeups: UInt64
    let diskReadBytes: UInt64
    let diskWriteBytes: UInt64
}

struct Report: Codable {
    let label: String
    let pid: Int32
    let processStartCounter: UInt64
    let capturedAt: Date
    let os: String
    let logicalCPUCount: Int
    let durationSeconds: Double
    let intervalSeconds: Double
    let sampleCount: Int
    let cpuSeconds: Double
    let averageCPUPercentOneCore: Double
    let initialFootprintBytes: UInt64
    let finalFootprintBytes: UInt64
    let peakSampledFootprintBytes: UInt64
    let peakSampledResidentBytes: UInt64
    let packageIdleWakeups: UInt64
    let interruptWakeups: UInt64
    let diskReadBytes: UInt64
    let diskWriteBytes: UInt64
    let batteryStart: String
    let batteryEnd: String
    let notes: [String]
    let samples: [Sample]
}

func usage() -> Never {
    fputs("Usage: mwitch-profile --pid PID [--duration 60] [--interval 1] [--label idle] [--output build/benchmarks/run]\n", stderr)
    exit(2)
}

func readUsage(_ pid: Int32) throws -> rusage_info_v2 {
    var info = rusage_info_v2()
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
        }
    }
    guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    guard info.ri_proc_exit_abstime == 0 else {
        throw NSError(domain: "Profile", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Process has exited."])
    }
    return info
}

func batteryStatus() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g", "batt"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    } catch { return "Unavailable: \(error)" }
}

var options: [String: String] = [:]
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let key = args.removeFirst()
    guard ["--pid", "--duration", "--interval", "--label", "--output"].contains(key),
          !args.isEmpty, options[key] == nil else { usage() }
    options[key] = args.removeFirst()
}
guard let pid = Int32(options["--pid"] ?? ""), pid > 0,
      let duration = Double(options["--duration"] ?? "60"), duration.isFinite, duration > 0,
      let interval = Double(options["--interval"] ?? "1"), interval.isFinite, interval >= 0.1,
      interval <= duration else { usage() }
let label = options["--label"] ?? "idle"
let output = options["--output"] ?? "build/benchmarks/\(Int(Date().timeIntervalSince1970))"
let outputURL = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                      withIntermediateDirectories: true)
let batteryStart = batteryStatus()
let capturedAt = Date()
let initial: rusage_info_v2
do { initial = try readUsage(pid) }
catch {
    fputs("Cannot sample PID \(pid): \(error)\n", stderr)
    exit(1)
}
let start = ProcessInfo.processInfo.systemUptime
var samples: [Sample] = []
var last = initial

func sample(_ info: rusage_info_v2, elapsed: Double) -> Sample {
    Sample(elapsedSeconds: elapsed,
           cpuSeconds: Double(info.ri_user_time + info.ri_system_time) / 1e9,
           residentBytes: info.ri_resident_size, footprintBytes: info.ri_phys_footprint,
           packageIdleWakeups: info.ri_pkg_idle_wkups, interruptWakeups: info.ri_interrupt_wkups,
           diskReadBytes: info.ri_diskio_bytesread, diskWriteBytes: info.ri_diskio_byteswritten)
}

samples.append(sample(initial, elapsed: 0))
print("Profiling PID \(pid), label \(label), for \(duration)s. Keep the workload consistent.")
do {
    while ProcessInfo.processInfo.systemUptime - start < duration {
        let remaining = duration - (ProcessInfo.processInfo.systemUptime - start)
        if remaining > 0 { Thread.sleep(forTimeInterval: min(interval, remaining)) }
        last = try readUsage(pid)
        guard last.ri_proc_start_abstime == initial.ri_proc_start_abstime else {
            throw NSError(domain: "Profile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "PID was reused; refusing to mix processes."])
        }
        samples.append(sample(last, elapsed: ProcessInfo.processInfo.systemUptime - start))
    }
} catch {
    fputs("Profile failed (process exited or could not be sampled): \(error)\n", stderr)
    exit(1)
}
let elapsed = samples.last!.elapsedSeconds
let cpu = Double((last.ri_user_time - initial.ri_user_time) +
                 (last.ri_system_time - initial.ri_system_time)) / 1e9
let report = Report(
    label: label, pid: pid, processStartCounter: initial.ri_proc_start_abstime,
    capturedAt: capturedAt, os: ProcessInfo.processInfo.operatingSystemVersionString,
    logicalCPUCount: ProcessInfo.processInfo.processorCount, durationSeconds: elapsed,
    intervalSeconds: interval, sampleCount: samples.count, cpuSeconds: cpu,
    averageCPUPercentOneCore: cpu / elapsed * 100,
    initialFootprintBytes: initial.ri_phys_footprint, finalFootprintBytes: last.ri_phys_footprint,
    peakSampledFootprintBytes: samples.map(\.footprintBytes).max()!,
    peakSampledResidentBytes: samples.map(\.residentBytes).max()!,
    packageIdleWakeups: last.ri_pkg_idle_wkups - initial.ri_pkg_idle_wkups,
    interruptWakeups: last.ri_interrupt_wkups - initial.ri_interrupt_wkups,
    diskReadBytes: last.ri_diskio_bytesread - initial.ri_diskio_bytesread,
    diskWriteBytes: last.ri_diskio_byteswritten - initial.ri_diskio_byteswritten,
    batteryStart: batteryStart, batteryEnd: batteryStatus(),
    notes: [
        "CPU percent uses one logical core as 100%; may exceed 100%.",
        "Peaks are sampled, not lifetime peaks. Physical footprint and RSS are different measurements.",
        "Only the selected process is measured; WindowServer and other apps are excluded.",
        "Wakeups are energy proxies, not joules or per-app battery drain.",
        "Battery status describes the entire machine; short runs cannot establish battery drain."
    ], samples: samples)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
try encoder.encode(report).write(to: outputURL.appendingPathExtension("json"))
var csv = "elapsed_seconds,cpu_seconds_cumulative,resident_bytes,footprint_bytes,package_idle_wakeups_cumulative,interrupt_wakeups_cumulative,disk_read_bytes_cumulative,disk_write_bytes_cumulative\n"
for s in samples {
    csv += "\(s.elapsedSeconds),\(s.cpuSeconds),\(s.residentBytes),\(s.footprintBytes),\(s.packageIdleWakeups),\(s.interruptWakeups),\(s.diskReadBytes),\(s.diskWriteBytes)\n"
}
try csv.write(to: outputURL.appendingPathExtension("csv"), atomically: true, encoding: .utf8)
print("Saved \(output).json and \(output).csv")
