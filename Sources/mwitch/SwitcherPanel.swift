import Cocoa
import SwiftUI

/// Where the switcher sits on a screen: horizontally centered, vertically
/// biased into the top half (Spotlight-style) rather than dead center.
enum SwitcherPanelLayout {
    /// The panel's vertical center sits at this fraction of the visible frame
    /// height, measured from the bottom. 0.5 would be dead center.
    static let verticalCenterBias: CGFloat = 0.62
    /// Tall lists are clamped so they never come closer than this to an edge.
    static let edgeMargin: CGFloat = 24

    static func origin(panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let x = visibleFrame.midX - panelSize.width / 2
        let idealY = visibleFrame.minY + visibleFrame.height * verticalCenterBias - panelSize.height / 2
        let topMost = visibleFrame.maxY - edgeMargin - panelSize.height
        let y = max(visibleFrame.minY + edgeMargin, min(idealY, topMost))
        return NSPoint(x: x, y: y)
    }
}

/// Selection changes keep these inputs unchanged; display changes invalidate them.
struct SwitcherPanelSizeState {
    private var entryCount: Int?
    private var visibleFrame: NSRect?

    mutating func needsResize(entryCount: Int, visibleFrame: NSRect) -> Bool {
        guard self.entryCount != entryCount || self.visibleFrame != visibleFrame else { return false }
        self.entryCount = entryCount
        self.visibleFrame = visibleFrame
        return true
    }
}

/// Floating panel with the row layout:
///     [app icon] [window title]
/// Release Cmd commits the current selection.
final class SwitcherPanel: NSPanel {
    private weak var panelDelegate: SwitcherPanelDelegate?

    /// The screen this panel is pinned to while presented. The controller shows
    /// one panel per display; nil falls back to the screen under the mouse.
    private var assignedScreen: NSScreen?

    private var hostingView: NSHostingView<SwitcherPanelView>?
    private var snapshot = SwitcherPanelSnapshot.empty
    private var sizeState = SwitcherPanelSizeState()

    private var keyMonitor: Any?
    private var scrollRequestID = 0

    private let rowHeight: CGFloat = 48
    private let panelWidth: CGFloat = 640
    private let cornerRadius: CGFloat = SwitcherPanelView.cornerRadius
    private let selectionInsetX: CGFloat = 8
    private let selectionInsetY: CGFloat = 4
    private let selectionCornerRadius: CGFloat = 12

    init(delegate: SwitcherPanelDelegate) {
        self.panelDelegate = delegate
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        animationBehavior = .none

        setupContent()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private func setupContent() {
        guard let content = contentView else { return }
        let host = NSHostingView(rootView: makePanelView())
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.cornerRadius = cornerRadius
        host.layer?.masksToBounds = true
        content.addSubview(host)
        hostingView = host
    }

    // MARK: - Lifecycle

    func render(_ snapshot: SwitcherPanelSnapshot, scrollTarget: Int? = nil) {
        self.snapshot = snapshot
        sizeToContents()
        renderContent(scrollTarget: scrollTarget)
    }

    func renderSelection(_ selectedRow: Int?, scrollTarget: Int? = nil) {
        var next = snapshot
        next.selectedRow = selectedRow
        render(next, scrollTarget: scrollTarget)
    }

    /// Call once after init to pre-warm the WindowServer connection. Subsequent
    /// `present()` calls reuse the connection and are noticeably faster.
    /// Only the primary panel may call this: it installs an app-wide key
    /// monitor, and a second one would double every keystroke.
    func preWarm() {
        installKeyMonitor()
        // Force the window backing store to be created up front.
        _ = self.contentView
    }

    /// Shows the panel on the given screen. Exactly one panel per session may
    /// pass `makeKeyPanel: true`; mirrors on other displays stay non-key so
    /// keyboard input has a single owner.
    func present(_ snapshot: SwitcherPanelSnapshot, on screen: NSScreen?, makeKeyPanel: Bool = true) {
        assignedScreen = screen
        render(snapshot, scrollTarget: snapshot.selectedRow)
        position()
        orderFrontRegardless()
        if makeKeyPanel {
            makeKey()
        }
    }

    func dismiss() {
        orderOut(nil)
    }

    // MARK: - Layout

    private func sizeToContents() {
        guard let screen = layoutScreen(),
              sizeState.needsResize(entryCount: snapshot.entries.count, visibleFrame: screen.visibleFrame)
        else { return }
        let usable = screen.visibleFrame.height - 120
        let rowsHeight = CGFloat(max(1, snapshot.entries.count)) * rowHeight
        let chrome: CGFloat = 16
        let desired = rowsHeight + chrome
        let height = min(usable, max(rowHeight + chrome, desired))
        let size = NSSize(width: panelWidth, height: height)
        if frame.size != size {
            var f = frame
            f.size = size
            setFrame(f, display: false)
        }
    }

    private func position() {
        guard let screen = layoutScreen() else { return }
        setFrameOrigin(SwitcherPanelLayout.origin(panelSize: frame.size, visibleFrame: screen.visibleFrame))
    }

    private func layoutScreen() -> NSScreen? {
        // AppKit invalidates NSScreen objects on display reconfiguration. If the
        // assigned display was unplugged mid-session, a stale object reports a
        // dead frame — which would size the panel from a bogus height and place
        // it at coordinates that no longer exist — so fall through and re-resolve.
        if let assignedScreen, NSScreen.screens.contains(where: { $0 === assignedScreen }) {
            return assignedScreen
        }
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.panelIsActive else { return event }
            if self.handleKeyDown(event) { return nil }
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            panelDelegate?.switcherPanel(self, didPerform: .cancel)
            return true
        case 36, 76: // Return / numpad Enter
            panelDelegate?.switcherPanel(self, didPerform: .commit)
            return true
        case 125: // Down
            panelDelegate?.switcherPanel(self, didPerform: .moveSelection(delta: 1))
            return true
        case 126: // Up
            panelDelegate?.switcherPanel(self, didPerform: .moveSelection(delta: -1))
            return true
        case 48: // Tab
            panelDelegate?.switcherPanel(
                self,
                didPerform: .moveSelection(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            )
            return true
        default:
            return false
        }
    }

    private func renderContent(scrollTarget: Int? = nil) {
        if scrollTarget != nil { scrollRequestID += 1 }
        hostingView?.rootView = makePanelView(scrollTarget: scrollTarget)
    }

    private func makePanelView(scrollTarget: Int? = nil) -> SwitcherPanelView {
        SwitcherPanelView(
            entries: snapshot.entries,
            selectedRow: snapshot.selectedRow,
            scrollTarget: scrollTarget,
            scrollRequestID: scrollRequestID,
            rowHeight: rowHeight,
            selectionInsetX: selectionInsetX,
            selectionInsetY: selectionInsetY,
            selectionCornerRadius: selectionCornerRadius,
            onCommit: { [weak self] row in
                guard let self else { return }
                self.panelDelegate?.switcherPanel(self, didPerform: .commitRow(row))
            }
        )
    }

    private var panelIsActive: Bool { panelDelegate?.switcherPanelIsActive ?? false }
}
