import Cocoa
import XCTest
@testable import mwitch

final class WindowActionsTests: XCTestCase {
    func testCloseTargetsExactWindowRatherThanAnotherCandidate() {
        let other = AXUIElementCreateApplication(101)
        let target = AXUIElementCreateApplication(102)
        var closed: AXUIElement?
        let success = WindowActions.closeWindow(
            entry,
            windows: { pid in
                XCTAssertEqual(pid, 222)
                return [other, target]
            },
            windowID: { CFEqual($0, target) ? 77 : 76 },
            pressClose: { closed = $0; return true }
        )
        XCTAssertTrue(success)
        XCTAssertTrue(closed.map { CFEqual($0, target) } ?? false)
    }

    func testMissingWindowDoesNotCloseAnotherWindow() {
        let other = AXUIElementCreateApplication(101)
        var attempts = 0
        XCTAssertFalse(WindowActions.closeWindow(
            entry, windows: { _ in [other] }, windowID: { _ in 76 },
            pressClose: { _ in attempts += 1; return true }
        ))
        XCTAssertEqual(attempts, 0)
    }

    func testUnresolvableWindowDoesNotPressClose() {
        let other = AXUIElementCreateApplication(101)
        XCTAssertFalse(WindowActions.closeWindow(
            entry, windows: { _ in [other] }, windowID: { _ in nil },
            pressClose: { _ in XCTFail("Must not close without an exact ID"); return true }
        ))
    }

    func testFailedCloseIsReported() {
        let target = AXUIElementCreateApplication(102)
        XCTAssertFalse(WindowActions.closeWindow(
            entry, windows: { _ in [target] }, windowID: { _ in 77 }, pressClose: { _ in false }
        ))
    }

    private var entry: WindowEntry {
        WindowEntry(cgWindowID: 77, pid: 222, appName: "App",
                    appIcon: nil, title: "Duplicate title", bundleID: nil)
    }
}
