import Foundation

/// Tiny diagnostic logger — writes to ~/Library/Logs/mwitch.log so we can see
/// what the (UI-less) app is doing without launching it from a terminal.
final class MwitchLog {
    static let shared = MwitchLog()
    private let url: URL
    private let formatter: DateFormatter
    private let queue = DispatchQueue(label: "dev.mwitch.log")

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("mwitch.log")
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    func line(_ msg: String) {
        queue.async { [self] in
            let stamp = formatter.string(from: Date())
            guard let data = "[\(stamp)] \(msg)\n".data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                // Keep one small diagnostic file rather than growing forever.
                if handle.seekToEndOfFile() > 1_048_576 {
                    try? handle.truncate(atOffset: 0)
                    try? handle.seek(toOffset: 0)
                }
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
