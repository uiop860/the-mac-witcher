import XCTest
@testable import mwitch

final class SwitcherListStateTests: XCTestCase {
    func testNavigationWrapsAtBothEnds() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build")
        ]
        _ = state.update(entries: entries, selection: 2)

        XCTAssertEqual(state.moveSelection(by: 1), 0)
        XCTAssertEqual(state.moveSelection(by: -1), 2)
        XCTAssertEqual(state.snapshot.entries, entries)
        XCTAssertEqual(state.snapshot.selectedRow, 2)
    }

    func testEmptyListHasNoSelection() {
        var state = SwitcherListState()
        XCTAssertNil(state.update(entries: [], selection: 0))
        XCTAssertNil(state.moveSelection(by: 1))
        XCTAssertNil(state.moveSelection(by: -1))
    }

    func testInvalidSelectionClearsPreviousSelection() {
        var state = SwitcherListState()
        _ = state.update(entries: [entry(id: 1, app: "Safari", title: "Docs")], selection: 0)
        XCTAssertNil(state.selectRow(10))
        XCTAssertNil(state.snapshot.selectedRow)
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
