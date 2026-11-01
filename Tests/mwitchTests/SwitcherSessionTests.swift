import XCTest
@testable import mwitch

final class SwitcherSessionTests: XCTestCase {
    func testStartSelectsMostRecentBackgroundWindow() {
        var session = SwitcherSession()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build")
        ]

        let result = session.start(entries: entries)

        XCTAssertEqual(result, .render(scrollTarget: 1))
        XCTAssertTrue(session.isVisible)
        XCTAssertEqual(session.selection, 1)
        XCTAssertEqual(session.snapshot.selectedRow, 1)
    }

    func testOpeningInReverseSelectsLastWindow() {
        var session = SwitcherSession()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build")
        ]
        XCTAssertEqual(session.start(entries: entries, reverse: true), .render(scrollTarget: 2))
        XCTAssertEqual(session.selection, 2)
    }

    func testOpeningSingleWindowInEitherDirectionSelectsIt() {
        for reverse in [false, true] {
            var session = SwitcherSession()
            XCTAssertEqual(
                session.start(entries: [entry(id: 1, app: "Safari", title: "Docs")], reverse: reverse),
                .render(scrollTarget: 0)
            )
        }
    }

    func testMoveSelectionAdvancesWithinVisibleRows() {
        var session = startedSession()

        let result = session.perform(.moveSelection(delta: 1))

        XCTAssertEqual(result, .render(scrollTarget: 2))
        XCTAssertEqual(session.selection, 2)
        XCTAssertEqual(session.snapshot.selectedRow, 2)
    }

    func testRefreshRemovesClosedWindowAndSelectsNextRow() {
        var session = startedSession()
        let remaining = session.entries.filter { $0.cgWindowID != 2 }
        XCTAssertEqual(session.refresh(entries: remaining), .render(scrollTarget: 1))
        XCTAssertTrue(session.isVisible)
        XCTAssertEqual(session.selectedEntry?.cgWindowID, 3)
    }

    func testRefreshKeepsSelectionAndStableOrderDespiteEnumerationReordering() {
        var session = startedSession()
        let reversed = Array(session.entries.reversed())
        XCTAssertEqual(session.refresh(entries: reversed), .render(scrollTarget: 1))
        XCTAssertEqual(session.entries.map(\.cgWindowID), [1, 2, 3, 4])
        XCTAssertEqual(session.selectedEntry?.cgWindowID, 2)
    }

    func testRefreshSelectsPreviousRowWhenLastWindowDisappears() {
        var session = startedSession()
        _ = session.perform(.moveSelection(delta: 2))
        let remaining = session.entries.filter { $0.cgWindowID != 4 }
        XCTAssertEqual(session.refresh(entries: remaining), .render(scrollTarget: 2))
        XCTAssertEqual(session.selectedEntry?.cgWindowID, 3)
    }

    func testRefreshPreservesNewKeyboardSelectionWhileCloseIsPending() {
        var session = startedSession()
        let remaining = session.entries.filter { $0.cgWindowID != 2 }
        _ = session.perform(.moveSelection(delta: 2))
        XCTAssertEqual(session.refresh(entries: remaining), .render(scrollTarget: 2))
        XCTAssertEqual(session.selectedEntry?.cgWindowID, 4)
    }

    func testRefreshRetainsWindowWhenCloseWasDeclined() {
        var session = startedSession()
        XCTAssertEqual(session.refresh(entries: session.entries), .render(scrollTarget: 1))
        XCTAssertEqual(session.selectedEntry?.cgWindowID, 2)
        XCTAssertTrue(session.isVisible)
    }

    func testRefreshHandlesSeveralQuitWindowsAndAppendsNewWindows() {
        var session = SwitcherSession()
        let windows = [
            entry(id: 1, app: "Safari", title: "One"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Mail", title: "Draft")
        ]
        _ = session.start(entries: windows)
        let new = entry(id: 4, app: "Terminal", title: "New")
        XCTAssertEqual(session.refresh(entries: [new, windows[0]]), .render(scrollTarget: 1))
        XCTAssertEqual(session.entries.map(\.cgWindowID), [1, 4])
    }

    func testRefreshDismissesOnlyWhenNoWindowsRemain() {
        var session = startedSession()
        XCTAssertEqual(session.refresh(entries: []), .dismiss(chosen: nil))
        XCTAssertFalse(session.isVisible)
        XCTAssertTrue(session.entries.isEmpty)
    }

    func testLateRefreshCannotReopenCancelledSession() {
        var session = startedSession()
        let windows = session.entries
        _ = session.perform(.cancel)
        XCTAssertEqual(session.refresh(entries: windows), .none)
        XCTAssertFalse(session.isVisible)
    }

    func testClickCommitsTheClickedWindow() {
        var session = startedSession()
        let result = session.perform(.commitRow(3))
        XCTAssertEqual(result, .dismiss(chosen: entry(id: 4, app: "TextEdit", title: "Draft")))
        XCTAssertFalse(session.isVisible)
    }

    func testWindowActionTargetFollowsKeyboardSelection() {
        var session = startedSession()
        XCTAssertEqual(session.selectedEntry?.cgWindowID, 2)
        _ = session.perform(.moveSelection(delta: 1))
        XCTAssertEqual(session.selectedEntry?.cgWindowID, 3)
        _ = session.perform(.cancel)
        XCTAssertFalse(session.isVisible)
    }

    func testCommitReturnsSelectedEntryAndHidesSession() {
        var session = startedSession()

        let result = session.perform(.commit)

        XCTAssertEqual(result, .dismiss(chosen: entry(id: 2, app: "Mail", title: "Inbox")))
        XCTAssertFalse(session.isVisible)
    }

    func testCommitRowIgnoresInvalidRow() {
        var session = startedSession()

        let result = session.perform(.commitRow(10))

        XCTAssertEqual(result, .none)
        XCTAssertTrue(session.isVisible)
        XCTAssertEqual(session.selection, 1)
    }

    func testCancelHidesWithoutChoosingEntry() {
        var session = startedSession()

        let result = session.perform(.cancel)

        XCTAssertEqual(result, .dismiss(chosen: nil))
        XCTAssertFalse(session.isVisible)
    }

    private func startedSession() -> SwitcherSession {
        var session = SwitcherSession()
        _ = session.start(entries: [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build"),
            entry(id: 4, app: "TextEdit", title: "Draft")
        ])
        return session
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
