import XCTest
@testable import mwitch

final class WindowRecencyTrackerTests: XCTestCase {
    func testSortsMostRecentlyUsedFirstAndUngroupsApps() {
        // z-order groups an app's windows together: [a1, a2, b1].
        let zOrder = [
            entry(id: 1, app: "AppA", title: "a1"),
            entry(id: 2, app: "AppA", title: "a2"),
            entry(id: 3, app: "AppB", title: "b1"),
        ]
        let tracker = WindowRecencyTracker()

        // Usage: focus a1, then b1, then a2 — a2 is now most recent.
        tracker.record(1)
        tracker.record(3)
        tracker.record(2)

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [2, 3, 1])
    }

    func testUnseenWindowsKeepZOrderAfterKnownOnes() {
        let zOrder = [
            entry(id: 1, app: "AppA", title: "a1"),
            entry(id: 2, app: "AppB", title: "b1"),
            entry(id: 3, app: "AppC", title: "c1"),
        ]
        let tracker = WindowRecencyTracker()
        tracker.record(3) // only AppC's window has been used

        // Used window leads; the rest keep their original relative order.
        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [3, 1, 2])
    }

    func testRecordingExistingWindowMovesItToFront() {
        let zOrder = [
            entry(id: 1, app: "AppA", title: "a1"),
            entry(id: 2, app: "AppB", title: "b1"),
        ]
        let tracker = WindowRecencyTracker()
        tracker.record(1)
        tracker.record(2)
        tracker.record(1) // re-using a1 promotes it without duplicating

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [1, 2])
    }

    func testRecordsFocusedWindowByPIDForAppLevelAXNotifications() {
        let zOrder = [
            entry(id: 1, app: "Arc", title: "Project"),
            entry(id: 2, app: "Arc", title: "Docs"),
            entry(id: 3, app: "Terminal", title: "Build"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.recordFocusedWindow(pid: 100) { pid in
            pid == 100 ? 2 : nil
        }

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [2, 1, 3])
    }

    func testDoesNotRecordOwnFocusedWindow() {
        let zOrder = [
            entry(id: 2, app: "Arc", title: "Docs"),
            entry(id: 1, app: "mwitch", title: "Panel"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 100)

        tracker.recordFocusedWindow(pid: 100) { _ in 1 }

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [2, 1])
    }

    func testRefreshesFrontmostWindow() {
        let zOrder = [
            entry(id: 1, app: "Arc", title: "Project"),
            entry(id: 2, app: "Arc", title: "Docs"),
            entry(id: 3, app: "Terminal", title: "Build"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.refreshFrontmostWindow(pid: 100) { pid in
            pid == 100 ? 2 : nil
        }

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [2, 1, 3])
    }

    func testDoesNotRefreshWhenThereIsNoActiveWindow() {
        let zOrder = [
            entry(id: 1, app: "Arc", title: "Project"),
            entry(id: 2, app: "Terminal", title: "Build"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.refreshFrontmostWindow(pid: nil) { _ in 1 }

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [1, 2])
    }

    func testRefreshBeforeOpeningCorrectsMissedFocusNotification() {
        let zOrder = [
            entry(id: 1, app: "Arc", title: "Project"),
            entry(id: 2, app: "Terminal", title: "Build"),
            entry(id: 3, app: "Arc", title: "Docs"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.record(1)
        tracker.record(2)

        // The AX notification for the latest Arc focus was missed. The
        // synchronous refresh performed when Cmd+Tab opens repairs the head of
        // the MRU list while retaining the previously observed window order.
        tracker.refreshFrontmostWindow(pid: 100) { pid in
            pid == 100 ? 3 : nil
        }

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [3, 2, 1])
    }

    // MARK: - Native tab surfaces (Ghostty, Terminal)

    func testResolvesFocusedTabSurfaceToTheListedWindow() {
        // Ghostty backs each tab with its own off-screen CG window. AX reports
        // the focused tab surface (132), which the enumerator drops, so it is
        // absent from the list. Recording it would seat an id that never
        // appears in the list at the head of the MRU order.
        let listed = [
            entry(id: 15746, app: "Ghostty", title: "Rudder: mwitch"),
            entry(id: 20, app: "Arc", title: "Slack"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.refreshFrontmostWindow(pid: 620, entries: listed, lookup: { $0 == 620 ? 132 : nil })

        // Index zero must be the window the user is actually looking at, so
        // index one — what Cmd+Tab preselects — is the previous window.
        XCTAssertEqual(tracker.sorted(listed).map(\.cgWindowID), [15746, 20])
    }

    func testDoesNotRemapAFocusedWindowOnAnotherSpace() {
        // A real window parked on another Space or in a full-screen Space is
        // kept by the enumerator and so IS in the list, even though it is not
        // in the current Space's on-screen windows. It must be recorded as-is:
        // remapping it onto the app's other window would put index zero on a
        // window the user is not in — the tab-surface bug inverted.
        let fullScreen = entry(id: 900, app: "Ghostty", title: "full-screen window")
        let listed = [
            entry(id: 44, app: "Ghostty", title: "desktop window"),
            fullScreen,
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.refreshFrontmostWindow(pid: 620, entries: listed, lookup: { $0 == 620 ? 900 : nil })

        XCTAssertEqual(tracker.sorted(listed).map(\.cgWindowID), [900, 44])
    }

    func testKeepsFocusedWindowWhenItIsListed() {
        let listed = [
            entry(id: 1, app: "Arc", title: "Project"),
            entry(id: 2, app: "Arc", title: "Docs"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.refreshFrontmostWindow(pid: 100, entries: listed, lookup: { $0 == 100 ? 2 : nil })

        XCTAssertEqual(tracker.sorted(listed).map(\.cgWindowID), [2, 1])
    }

    func testKeepsFocusedWindowWhenTheAppHasNoListedWindows() {
        // Nothing to remap onto — keep what AX reported rather than guess.
        let listed = [entry(id: 8, app: "Arc", title: "Slack")]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.refreshFrontmostWindow(pid: 863, entries: listed, lookup: { $0 == 863 ? 7 : nil })

        XCTAssertEqual(tracker.sorted(listed + [entry(id: 7, app: "Beeper", title: "Beeper")])
            .map(\.cgWindowID), [7, 8])
    }

    func testResolvedTabSurfaceIsNotRecordedForOwnProcess() {
        let listed = [
            entry(id: 5, app: "Arc", title: "Slack"),
            entry(id: 6, app: "mwitch", title: "Panel"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 100)

        tracker.refreshFrontmostWindow(pid: 100, entries: listed, lookup: { _ in 999 })

        XCTAssertEqual(tracker.sorted(listed).map(\.cgWindowID), [5, 6])
    }

    private func entry(id: CGWindowID, app: String, title: String) -> WindowEntry {
        WindowEntry(
            cgWindowID: id,
            pid: pid_t(id),
            appName: app,
            appIcon: nil,
            title: title,
            bundleID: nil
        )
    }
}
