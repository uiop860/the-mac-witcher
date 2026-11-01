import AppKit
import XCTest
@testable import mwitch

final class SwitcherPanelLayoutTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1728, height: 1080)

    func testSelectionUpdatesDoNotRequestRepeatedResize() {
        var state = SwitcherPanelSizeState()
        XCTAssertTrue(state.needsResize(entryCount: 100, visibleFrame: screen))
        for _ in 0..<100 {
            XCTAssertFalse(state.needsResize(entryCount: 100, visibleFrame: screen))
        }
        XCTAssertTrue(state.needsResize(entryCount: 50, visibleFrame: screen))
    }

    func testDisplayGeometryChangeInvalidatesSize() {
        var state = SwitcherPanelSizeState()
        XCTAssertTrue(state.needsResize(entryCount: 100, visibleFrame: screen))
        let smaller = NSRect(x: 1728, y: 0, width: 1280, height: 720)
        XCTAssertTrue(state.needsResize(entryCount: 100, visibleFrame: smaller))
        XCTAssertFalse(state.needsResize(entryCount: 100, visibleFrame: smaller))
    }

    func testPanelCenterSitsAboveScreenCenter() {
        let size = NSSize(width: 620, height: 400)
        let origin = SwitcherPanelLayout.origin(panelSize: size, visibleFrame: screen)

        let panelMidY = origin.y + size.height / 2
        XCTAssertGreaterThan(panelMidY, screen.midY)
        XCTAssertEqual(panelMidY, screen.height * SwitcherPanelLayout.verticalCenterBias, accuracy: 0.5)
    }

    func testPanelIsHorizontallyCentered() {
        let size = NSSize(width: 620, height: 400)
        let origin = SwitcherPanelLayout.origin(panelSize: size, visibleFrame: screen)

        XCTAssertEqual(origin.x + size.width / 2, screen.midX, accuracy: 0.5)
    }

    func testTallPanelIsClampedInsideTheScreen() {
        let size = NSSize(width: 620, height: screen.height - 60)
        let origin = SwitcherPanelLayout.origin(panelSize: size, visibleFrame: screen)

        XCTAssertGreaterThanOrEqual(origin.y, screen.minY + SwitcherPanelLayout.edgeMargin - 0.5)
        XCTAssertLessThanOrEqual(
            origin.y + size.height,
            screen.maxY - SwitcherPanelLayout.edgeMargin + 0.5
        )
    }

    func testOffsetVisibleFrameIsRespected() {
        // A secondary display arranged to the right and up, with a Dock inset.
        let offset = NSRect(x: 1728, y: 200, width: 2560, height: 1340)
        let size = NSSize(width: 620, height: 300)
        let origin = SwitcherPanelLayout.origin(panelSize: size, visibleFrame: offset)

        XCTAssertEqual(origin.x + size.width / 2, offset.midX, accuracy: 0.5)
        let panelMidY = origin.y + size.height / 2
        XCTAssertEqual(
            panelMidY,
            offset.minY + offset.height * SwitcherPanelLayout.verticalCenterBias,
            accuracy: 0.5
        )
    }
}
