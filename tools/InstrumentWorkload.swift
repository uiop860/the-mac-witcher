import Cocoa

/// Synthetic on-screen panel workload for Instruments. Does not activate apps,
/// install a keyboard hook, enumerate private window titles, or change settings.
@main
struct InstrumentWorkload {
    static func main() {
        let app = NSApplication.shared
        let driver = PanelWorkload()
        app.delegate = driver
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(driver) {}
    }
}

final class PanelWorkload: NSObject, NSApplicationDelegate, SwitcherPanelDelegate {
    private var panel: SwitcherPanel!
    private var timer: Timer?
    private let scrollSelections = ProcessInfo.processInfo.environment["MWITCH_PROFILE_SCROLL"] != "0"
    private var step = 0
    private var started: TimeInterval = 0
    private var durations: [Double] = []
    private var windows: [WindowEntry] = []
    var switcherPanelIsActive: Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows = (1...100).map {
            WindowEntry(cgWindowID: CGWindowID($0), pid: 0, appName: "Synthetic app \($0 % 10)",
                        appIcon: nil, title: "Synthetic window \($0)", bundleID: nil)
        }
        panel = SwitcherPanel(delegate: self)
        started = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - started < 12 else {
            timer?.invalidate()
            panel.dismiss()
            let sorted = durations.sorted()
            print("Synthetic panel: \(durations.count) updates, median submission ms \(sorted[sorted.count / 2] * 1000), max submission ms \((sorted.last ?? 0) * 1000)")
            NSApplication.shared.terminate(nil)
            return
        }
        let begin = ProcessInfo.processInfo.systemUptime
        let position = step % 20
        if position == 0 {
            panel.present(.init(entries: windows, selectedRow: 0),
                          on: NSScreen.main, makeKeyPanel: false)
        } else if position < 16 {
            let row = (step * 7) % windows.count
            panel.renderSelection(row, scrollTarget: scrollSelections ? row : nil)
        } else if position == 16 {
            panel.dismiss()
        }
        if position < 16 { durations.append(ProcessInfo.processInfo.systemUptime - begin) }
        step += 1
    }

    func switcherPanel(_ panel: SwitcherPanel, didPerform action: SwitcherPanelAction) {
        // Synthetic row clicks never activate another process.
    }
}
