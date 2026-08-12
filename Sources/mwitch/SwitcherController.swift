import Cocoa

/// Owns the panel + currently-shown window list. Handles Cmd+Tab semantics:
/// first press = show panel with most-recent window selected; subsequent presses
/// advance selection; Cmd-up commits and activates.
final class SwitcherController {
    private var panel: SwitcherPanel?
    /// Read-only copies of the switcher shown on every display other than the
    /// one holding the key panel, so Cmd+Tab is visible wherever you look.
    /// They never call preWarm() — only the primary panel may own the app-wide
    /// key monitor.
    private var mirrorPanels: [SwitcherPanel] = []
    private var session = SwitcherSession()
    private var lastCommitUptime: TimeInterval = -.infinity

    var entries: [WindowEntry] { session.entries }
    var selection: Int { session.selection }
    var isVisible: Bool { session.isVisible }

    /// Pre-create the panel + warm the WindowServer connection so the first
    /// Cmd+Tab doesn't pay allocation cost.
    func preWarm() {
        if panel == nil {
            panel = SwitcherPanel(delegate: self)
            panel?.preWarm()
        }
        // Touch the window list once so AppKit caches its bookkeeping.
        _ = WindowEnumerator.enumerate()
    }

    func advance(reverse: Bool = false) {
        if !isVisible {
            // Right after a commit, activation is still asynchronous and the
            // workspace can report the window we just left as frontmost;
            // recording that would put it back at the MRU head and turn the
            // quick Cmd+Tab toggle into a no-op. The commit already recorded
            // the chosen window, so the cached order is correct — skip the
            // sync refresh until activation has had time to land.
            if ProcessInfo.processInfo.systemUptime - lastCommitUptime > 1.0 {
                WindowRecencyTracker.shared.refreshFrontmostWindow()
            }
            let entries = WindowRecencyTracker.shared.sorted(WindowEnumerator.enumerate())
            handle(session.start(entries: entries), presenting: true)
        } else {
            handle(session.perform(.moveSelection(delta: reverse ? -1 : 1)))
        }
    }

    func setSelection(_ index: Int, updatePanel: Bool = true) {
        let result = session.setSelection(index)
        if updatePanel { handle(result) }
    }

    func clearSelection(updatePanel: Bool = true) {
        let result = session.clearSelection()
        if updatePanel { handle(result) }
    }

    func commitIfVisible() {
        handle(session.perform(.commit))
    }

    func cancel() {
        handle(session.perform(.cancel))
    }

    private func show() {
        if panel == nil {
            panel = SwitcherPanel(delegate: self)
            panel?.preWarm()
        }
        guard let panel else { return }

        let screens = NSScreen.screens
        let active = Self.activeScreen(in: screens)
        let others = screens.filter { $0 !== active }

        // One mirror per extra display, created on demand and reused between
        // opens. The display list can change between sessions, so trim extras.
        while mirrorPanels.count < others.count {
            mirrorPanels.append(SwitcherPanel(delegate: self))
        }
        if mirrorPanels.count > others.count {
            for extra in mirrorPanels[others.count...] { extra.dismiss() }
            mirrorPanels.removeSubrange(others.count...)
        }

        renderPanel(scrollTarget: session.snapshot.selectedRow)
        for (mirror, screen) in zip(mirrorPanels, others) {
            mirror.present(on: screen, makeKeyPanel: false)
        }
        panel.present(on: active, makeKeyPanel: true)
    }

    /// The screen the key panel belongs on: under the mouse, else the main one.
    private static func activeScreen(in screens: [NSScreen]) -> NSScreen? {
        screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? screens.first
    }

    private func hide() {
        panel?.dismiss()
        for mirror in mirrorPanels { mirror.dismiss() }
    }

    private func renderPanel(scrollTarget: Int? = nil, reposition: Bool = false) {
        panel?.render(session.snapshot, scrollTarget: scrollTarget, reposition: reposition)
        for mirror in mirrorPanels {
            mirror.render(session.snapshot, scrollTarget: scrollTarget, reposition: reposition)
        }
    }

    private func handle(_ result: SwitcherSessionResult, presenting: Bool = false) {
        switch result {
        case .none:
            return
        case .render(let scrollTarget, let reposition):
            if presenting {
                show()
            } else {
                renderPanel(scrollTarget: scrollTarget, reposition: reposition)
            }
        case .dismiss(let chosen):
            hide()
            if let chosen {
                WindowActivator.activate(chosen)
                WindowRecencyTracker.shared.record(chosen.cgWindowID)
                lastCommitUptime = ProcessInfo.processInfo.systemUptime
            }
        }
    }
}

extension SwitcherController: SwitcherPanelDelegate {
    var switcherPanelIsActive: Bool { isVisible }

    func switcherPanel(_ panel: SwitcherPanel, didPerform action: SwitcherPanelAction) {
        handle(session.perform(action))
    }
}
