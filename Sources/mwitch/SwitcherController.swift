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
    private var refreshRevision = 0
    private var refreshWorkItem: DispatchWorkItem?
    private var pendingCommand: (SwitcherWindowCommand, WindowEntry)?
    private var commitAfterRefresh = false
    private var lastCommitUptime: TimeInterval = -.infinity

    var isVisible: Bool { session.isVisible }

    /// Pre-create the panel + warm the WindowServer connection so the first
    /// Cmd+Tab doesn't pay allocation cost.
    func preWarm() {
        if panel == nil {
            panel = SwitcherPanel(delegate: self)
            panel?.preWarm()
        }
    }

    func advance(reverse: Bool = false) {
        if !isVisible {
            // Reverse navigation only applies to an already-open switcher.
            guard !reverse else { return }

            // Right after a commit, activation is still asynchronous and the
            // workspace can report the window we just left as frontmost;
            // recording that would put it back at the MRU head and turn the
            // quick Cmd+Tab toggle into a no-op. The commit already recorded
            // the chosen window, so the cached order is correct — skip the
            // sync refresh until activation has had time to land.
            // Enumerate first: the focused window is resolved against the list
            // that is about to be shown, so a native-tab surface can be mapped
            // onto the window this session will actually display.
            let enumerated = WindowEnumerator.enumerate()
            if ProcessInfo.processInfo.systemUptime - lastCommitUptime > 1.0 {
                WindowRecencyTracker.shared.refreshFrontmostWindow(entries: enumerated)
            }
            let entries = WindowRecencyTracker.shared.sorted(enumerated)
            handle(session.start(entries: entries, reverse: reverse), presenting: true)
        } else {
            commitAfterRefresh = false
            handle(session.perform(.moveSelection(delta: reverse ? -1 : 1)))
        }
    }

    /// Keep the panel open while the app processes the request. Refresh only
    /// for this operation, rather than polling continuously while idle.
    func performWindowCommand(_ command: SwitcherWindowCommand) -> Bool {
        guard isVisible else { return false }
        guard let entry = session.selectedEntry else { return true }
        if let pending = pendingCommand,
           pending.0 == command, pending.1.cgWindowID == entry.cgWindowID { return true }
        commitAfterRefresh = false
        refreshRevision += 1
        let revision = refreshRevision
        refreshWorkItem?.cancel()
        pendingCommand = (command, entry)
        // Return from the event tap before potentially slow AX IPC.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, self.refreshRevision == revision else { return }
            let succeeded: Bool
            switch command {
            case .closeWindow: succeeded = WindowActions.closeWindow(entry)
            case .quitApplication: succeeded = WindowActions.quitApplication(entry)
            }
            if !succeeded { NSSound.beep() }
            self.refreshAfterWindowCommand(revision: revision, attemptsLeft: succeeded ? 10 : 0)
        }
        return true
    }

    private func refreshAfterWindowCommand(revision: Int, attemptsLeft: Int) {
        guard isVisible, revision == refreshRevision, let pending = pendingCommand else { return }
        handle(session.refresh(entries: WindowEnumerator.enumerate()))
        guard isVisible else { return }
        let targetStillPresent: Bool
        switch pending.0 {
        case .closeWindow:
            targetStillPresent = session.entries.contains { $0.cgWindowID == pending.1.cgWindowID }
        case .quitApplication:
            targetStillPresent = session.entries.contains { $0.pid == pending.1.pid }
        }
        if targetStillPresent && attemptsLeft > 0 {
            let work = DispatchWorkItem { [weak self] in
                self?.refreshAfterWindowCommand(revision: revision, attemptsLeft: attemptsLeft - 1)
            }
            refreshWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            pendingCommand = nil
            refreshWorkItem = nil
            if commitAfterRefresh {
                commitAfterRefresh = false
                handle(session.perform(.commit))
            }
        }
    }

    func commitIfVisible() {
        // Cmd can be released before the close/quit finishes. Avoid activating
        // a stale selection; commit the refreshed list instead.
        if pendingCommand != nil {
            commitAfterRefresh = true
        } else {
            handle(session.perform(.commit))
        }
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

        for (mirror, screen) in zip(mirrorPanels, others) {
            mirror.present(session.snapshot, on: screen, makeKeyPanel: false)
        }
        panel.present(session.snapshot, on: active, makeKeyPanel: true)
    }

    /// The screen the key panel belongs on: under the mouse, else the main one.
    ///
    /// `NSScreen.main` is a separate lookup and AppKit does not promise it is
    /// the same object as the matching element of `screens`. Since `show()`
    /// partitions the list by identity, an unmatched instance would leave the
    /// active display in `others` and stack a mirror underneath the key panel,
    /// so map it back onto the array by display id.
    private static func activeScreen(in screens: [NSScreen]) -> NSScreen? {
        if let underMouse = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return underMouse
        }
        if let mainID = NSScreen.main?.displayID,
           let match = screens.first(where: { $0.displayID == mainID }) {
            return match
        }
        return screens.first
    }

    private func hide() {
        panel?.dismiss()
        for mirror in mirrorPanels { mirror.dismiss() }
    }

    private func renderPanel(scrollTarget: Int? = nil) {
        panel?.render(session.snapshot, scrollTarget: scrollTarget)
        for mirror in mirrorPanels {
            mirror.render(session.snapshot, scrollTarget: scrollTarget)
        }
    }

    private func handle(_ result: SwitcherSessionResult, presenting: Bool = false) {
        switch result {
        case .none:
            return
        case .render(let scrollTarget):
            if presenting {
                show()
            } else {
                renderPanel(scrollTarget: scrollTarget)
            }
        case .dismiss(let chosen):
            refreshRevision += 1
            refreshWorkItem?.cancel()
            refreshWorkItem = nil
            pendingCommand = nil
            commitAfterRefresh = false
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
        switch action {
        case .commit:
            commitIfVisible()
        case .moveSelection:
            commitAfterRefresh = false
            handle(session.perform(action))
        default:
            handle(session.perform(action))
        }
    }
}

private extension NSScreen {
    /// Stable identifier for the physical display behind this `NSScreen`.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
