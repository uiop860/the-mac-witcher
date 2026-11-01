import Cocoa
import XCTest
@testable import mwitch

final class SwitcherWindowListTests: XCTestCase {
    func testKeyboardSelectionStaysFullyVisibleAcrossLongList() {
        let view = list()
        for row in [0, 1, 5, 6, 25, 99, 199, 198, 100, 0] {
            render(view, row: row)
            XCTAssertEqual(view.table.selectedRow, row)
            assertVisible(row, in: view)
        }
    }

    func testScrollbarHiddenWhenRowsExactlyFit() {
        for style in [NSScroller.Style.legacy, .overlay] {
            let view = list()
            view.scrollerStyle = style
            view.frame.size.height = 5 * view.table.rowHeight
            view.render(entries: Array(entries.prefix(5)), selectedRow: 1,
                        scrollTarget: 1, onCommit: { _ in })
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(view.table.frame.height, view.contentView.bounds.height + 0.5)
            XCTAssertTrue(view.verticalScroller?.isHidden ?? true)
        }
    }

    func testScrollbarAppearsOnlyWhileRowsOverflow() {
        let view = list()
        view.scrollerStyle = .legacy
        render(view, row: 0)
        XCTAssertFalse(view.verticalScroller?.isHidden ?? true)

        view.render(entries: Array(entries.prefix(2)), selectedRow: 0,
                    scrollTarget: 0, onCommit: { _ in })
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(view.verticalScroller?.isHidden ?? true)
    }

    func testColumnFillsViewportAndExposesRowLabels() {
        let view = list()
        render(view, row: 0)
        XCTAssertGreaterThan(view.table.tableColumns[0].width, 500)
        let cell = view.table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        XCTAssertEqual(cell?.accessibilityLabel(), "App, Window 0")
    }

    func testVisibleSelectionDoesNotMoveViewport() {
        let view = list()
        render(view, row: 100)
        let origin = view.contentView.bounds.origin
        let visible = view.table.rows(in: view.table.visibleRect)
        let row = visible.location + 1
        render(view, row: row)
        XCTAssertEqual(view.contentView.bounds.origin, origin)
        assertVisible(row, in: view)
    }

    func testSameSelectionIsRevealedAfterManualScrollingAndReuse() {
        let view = list()
        render(view, row: 199)
        view.contentView.scroll(to: .zero)
        view.reflectScrolledClipView(view.contentView)
        XCTAssertFalse(view.table.visibleRect.contains(view.table.rect(ofRow: 199)))

        render(view, row: 199)
        assertVisible(199, in: view)
    }

    func testRevealUsesFinalViewportSize() {
        let view = list()
        view.render(entries: entries, selectedRow: 150, scrollTarget: 150, onCommit: { _ in })
        view.setFrameSize(NSSize(width: 620, height: 120))
        view.layoutSubtreeIfNeeded()
        assertVisible(150, in: view)
    }

    func testHostedPanelRevealsSelectionAgainWhenReused() throws {
        _ = NSApplication.shared
        let delegate = ListTestDelegate()
        let panel = SwitcherPanel(delegate: delegate)
        defer { panel.close() }
        let snapshot = SwitcherPanelSnapshot(entries: entries, selectedRow: 199)
        panel.render(snapshot, scrollTarget: 199)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        panel.contentView?.layoutSubtreeIfNeeded()
        let list = try XCTUnwrap(findList(in: panel.contentView))
        assertVisible(199, in: list)
        list.contentView.scroll(to: .zero)
        list.reflectScrolledClipView(list.contentView)

        panel.render(snapshot, scrollTarget: 199)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        panel.contentView?.layoutSubtreeIfNeeded()

        assertVisible(199, in: list)
    }

    private func findList(in view: NSView?) -> SwitcherWindowListView? {
        guard let view else { return nil }
        if let list = view as? SwitcherWindowListView { return list }
        return view.subviews.lazy.compactMap { self.findList(in: $0) }.first
    }

    func testEmptyListAndInvalidSelectionDoNotScrollOrSelect() {
        let view = list()
        view.render(entries: [], selectedRow: 100, scrollTarget: 100, onCommit: { _ in })
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.table.numberOfRows, 0)
        XCTAssertEqual(view.table.selectedRow, -1)
    }

    private func list() -> SwitcherWindowListView {
        _ = NSApplication.shared
        let view = SwitcherWindowListView()
        view.frame = NSRect(x: 0, y: 0, width: 620, height: 200)
        return view
    }

    private var entries: [WindowEntry] {
        (0..<200).map {
            WindowEntry(cgWindowID: CGWindowID($0 + 1), pid: 1, appName: "App",
                        appIcon: nil, title: "Window \($0)", bundleID: nil)
        }
    }

    private func render(_ view: SwitcherWindowListView, row: Int) {
        view.render(entries: entries, selectedRow: row, scrollTarget: row, onCommit: { _ in })
        view.layoutSubtreeIfNeeded()
    }

    private func assertVisible(_ row: Int, in view: SwitcherWindowListView,
                               file: StaticString = #filePath, line: UInt = #line) {
        let rect = view.table.rect(ofRow: row)
        let visible = view.table.visibleRect
        XCTAssertGreaterThan(rect.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, visible.minY - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, visible.maxY + 0.5, file: file, line: line)
    }
}


private final class ListTestDelegate: SwitcherPanelDelegate {
    var switcherPanelIsActive: Bool { false }
    func switcherPanel(_ panel: SwitcherPanel, didPerform action: SwitcherPanelAction) {}
}
