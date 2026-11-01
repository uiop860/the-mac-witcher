import Cocoa
import XCTest
@testable import mwitch

/// Opt in with MWITCH_BENCHMARKS=1; run release builds on the same machine.
final class PerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MWITCH_BENCHMARKS"] == "1",
                          "Performance measurements are opt-in.")
    }

    func testSessionNavigation100Windows() {
        let windows = entries(count: 100)
        var checksum = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100_000 {
                var session = SwitcherSession()
                _ = session.start(entries: windows)
                for _ in 0..<100 { _ = session.perform(.moveSelection(delta: 1)) }
                checksum += session.selection
                _ = session.perform(.commit)
            }
        }
        XCTAssertGreaterThan(checksum, 0)
    }

    func testRecencySort500Windows() {
        let windows = entries(count: 500)
        let tracker = WindowRecencyTracker()
        for window in windows { tracker.record(window.cgWindowID) }
        var checksum = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for _ in 0..<1_000 {
                checksum += Int(tracker.sorted(windows).first!.cgWindowID)
            }
        }
        XCTAssertGreaterThan(checksum, 0)
    }

    func testEnumerationPolicy500Windows() {
        let windows = (1...500).map {
            WindowEnumerator.RawWindow(
                cgWindowID: CGWindowID($0), pid: pid_t(10 + $0 % 20),
                ownerName: "App", layer: 0, title: "Window \($0)",
                bounds: CGRect(x: 0, y: 0, width: 800, height: 600), isOnscreen: true
            )
        }
        var checksum = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for _ in 0..<1_000 {
                checksum += WindowEnumerator.entries(
                    onScreenWindows: windows, allWindows: windows, ownPID: -1,
                    axWindowsForPID: { _ in nil },
                    appMetaForPID: { _, name in .init(name: name, icon: nil, bundleID: nil) },
                    isAssignedToASpace: { _ in true }, isAppHidden: { _ in false }
                ).count
            }
        }
        XCTAssertGreaterThan(checksum, 0)
    }

    func testPanelSelectionUpdates100Windows() {
        _ = NSApplication.shared
        let delegate = BenchmarkPanelDelegate()
        let panel = SwitcherPanel(delegate: delegate)
        let windows = entries(count: 100)
        panel.render(.init(entries: windows, selectedRow: 0))
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for row in 0..<100 {
                panel.renderSelection(row, scrollTarget: row)
                // Let SwiftUI deliver observations instead of timing coalesced
                // submissions that never reach a layout pass.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
                panel.contentView?.layoutSubtreeIfNeeded()
            }
        }
        panel.close()
    }

    func testLiveWindowEnumeration() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MWITCH_LIVE_BENCHMARKS"] == "1",
                          "Live enumeration requires a controlled desktop and permissions.")
        try XCTSkipUnless(CGPreflightScreenCaptureAccess() && AXIsProcessTrusted(),
                          "Grant Screen Recording and Accessibility to the test runner first.")
        var count = 0
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            count = WindowEnumerator.enumerate().count
        }
        XCTAssertGreaterThan(count, 0, "Open at least one normal window for the live benchmark.")
    }

    private func entries(count: Int) -> [WindowEntry] {
        (1...count).map {
            WindowEntry(cgWindowID: CGWindowID($0), pid: pid_t(10 + $0 % 20),
                        appName: "App \($0 % 20)", appIcon: nil, title: "Window \($0)", bundleID: nil)
        }
    }
}


private final class BenchmarkPanelDelegate: SwitcherPanelDelegate {
    var switcherPanelIsActive: Bool { false }
    func switcherPanel(_ panel: SwitcherPanel, didPerform action: SwitcherPanelAction) {}
}
