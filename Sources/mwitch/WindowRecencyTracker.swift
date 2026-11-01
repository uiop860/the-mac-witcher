import Cocoa
import ApplicationServices

/// Global most-recently-used order of windows, keyed by CGWindowID.
///
/// CGWindowList only exposes z-order, which groups every window of an app
/// together because activating an app raises all its windows as a block. macOS
/// has no API for global per-window recency, so we build it ourselves:
///   - record each window mwitch activates,
///   - watch NSWorkspace app-activations to catch switches between apps made
///     outside mwitch (native Cmd+Tab, Dock, clicking another app), and
///   - watch each app's AX focused-window changes so clicking between two
///     windows of the *same* app reorders them too,
///   - synchronously confirm the focused window whenever the switcher opens.
final class WindowRecencyTracker {
    static let shared = WindowRecencyTracker()

    /// Most-recently-used first.
    private var order: [CGWindowID] = []
    private let maxEntries = 256
    private let ownPID: pid_t

    /// One AX observer per app PID, tracking its focused-window changes.
    private var observers: [pid_t: AXObserver] = [:]

    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    /// Begins observing app and window focus changes. Call once at launch.
    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appActivated(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appLaunched(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observeFocusChanges(pid: app.processIdentifier)
        }
        refreshFrontmostWindow(entries: WindowEnumerator.enumerate())
    }

    /// Marks a window as the most recently used.
    func record(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > maxEntries { order.removeLast(order.count - maxEntries) }
    }

    /// Reorders entries most-recently-used first. Windows never seen keep their
    /// original (z-order) relative position, appended after all known windows —
    /// so a freshly launched mwitch still shows a sensible list before any
    /// switches have been recorded.
    func sorted(_ entries: [WindowEntry]) -> [WindowEntry] {
        var rank: [CGWindowID: Int] = [:]
        for (index, id) in order.enumerated() { rank[id] = index }
        return entries.enumerated().sorted { lhs, rhs in
            switch (rank[lhs.element.cgWindowID], rank[rhs.element.cgWindowID]) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let pid = Self.pid(from: note) else { return }
        recordFocusedWindow(pid: pid, lookup: Self.focusedWindowID)
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let pid = Self.pid(from: note) else { return }
        observeFocusChanges(pid: pid)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let pid = Self.pid(from: note) else { return }
        stopTracking(pid: pid)
    }

    /// Release both observer and icon metadata when a process exits.
    func stopTracking(pid: pid_t) {
        stopObserving(pid: pid)
        WindowEnumerator.invalidate(pid: pid)
    }

    // MARK: - Per-app focused-window observers

    /// Fired by AX whenever an app's focused/main window changes, including
    /// clicking between two windows of the same app, which NSWorkspace never
    /// reports. Some apps send the changed window as `element`; others send the
    /// observed app element, so fall back to querying that app's focused window.
    private let focusChangedCallback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<WindowRecencyTracker>.fromOpaque(refcon).takeUnretainedValue()

        // Recorded as reported. Resolving a tab surface here would need a full
        // window list on the main run loop for every focus change of every
        // observed app; the synchronous refresh when the switcher opens does
        // that resolution once, against the list actually being shown. A stale
        // surface id further down the order is harmless because `sorted` only
        // ranks windows that are in the list.
        var winID: CGWindowID = 0
        if _AXUIElementGetWindow(element, &winID) == .success {
            tracker.record(winID)
            return
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        tracker.recordFocusedWindow(pid: pid, lookup: WindowRecencyTracker.focusedWindowID)
    }

    private func observeFocusChanges(pid: pid_t) {
        guard pid != ownPID, observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, focusChangedCallback, &observer) == .success,
              let observer else { return }

        let axApp = WindowAccessibility.application(pid: pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let focusedResult = AXObserverAddNotification(
            observer,
            axApp,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        let mainResult = AXObserverAddNotification(
            observer,
            axApp,
            kAXMainWindowChangedNotification as CFString,
            refcon
        )
        guard focusedResult == .success || mainResult == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stopObserving(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    // MARK: - Helpers

    private static func pid(from note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    func recordFocusedWindow(
        pid: pid_t,
        entries: [WindowEntry] = [],
        lookup: (pid_t) -> CGWindowID?
    ) {
        guard pid != ownPID, let id = lookup(pid) else { return }
        record(Self.switchableWindowID(for: id, pid: pid, entries: entries))
    }

    /// Maps an Accessibility focused-window ID onto a window the switcher is
    /// actually showing, resolved against `entries` — the exact list this
    /// session is about to display.
    ///
    /// In an app using native window tabbing (Ghostty, Terminal),
    /// `kAXFocusedWindowAttribute` reports the focused *tab's* backing surface
    /// rather than the window on screen. That surface is off-screen and
    /// AX-unresolvable, so the enumerator drops it as a dead tab surface.
    /// Recording it anyway seats an id that never appears in the list at the
    /// head of the MRU order, which silently breaks the "index zero is the
    /// current window" guarantee — leaving Cmd+Tab preselecting index one
    /// relative to the wrong window, so it lands somewhere arbitrary or looks
    /// like it did nothing.
    ///
    /// Resolving against `entries` rather than against the current Space's
    /// on-screen windows is what keeps this honest: `enumerate()` deliberately
    /// keeps real windows parked on other Spaces and in full-screen Spaces, and
    /// those are legitimately absent from the on-screen list. Treating them as
    /// tab surfaces would remap a genuine focused window onto a different one —
    /// the same bug inverted. Only an id the switcher will not show is remapped,
    /// onto that app's first listed window.
    static func switchableWindowID(
        for focused: CGWindowID,
        pid: pid_t,
        entries: [WindowEntry]
    ) -> CGWindowID {
        if entries.contains(where: { $0.cgWindowID == focused }) { return focused }
        guard let front = entries.first(where: { $0.pid == pid }) else { return focused }
        return front.cgWindowID
    }

    /// Captures the window that is actually focused at the point the switcher
    /// opens. This closes gaps from missed/delayed workspace or AX
    /// notifications and guarantees that index zero is the current window,
    /// making index one the previously used window.
    /// `entries` must be the enumeration about to be displayed, so the focused
    /// window is resolved against what the switcher will actually show.
    func refreshFrontmostWindow(entries: [WindowEntry]) {
        refreshFrontmostWindow(
            pid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            entries: entries,
            lookup: Self.focusedWindowID
        )
    }

    func refreshFrontmostWindow(
        pid: pid_t?,
        entries: [WindowEntry] = [],
        lookup: (pid_t) -> CGWindowID?
    ) {
        guard let pid else { return }
        recordFocusedWindow(pid: pid, entries: entries, lookup: lookup)
    }

    /// The CGWindowID of an app's focused window, via the same private API the
    /// enumerator and activator use to bridge AX windows to CGWindowIDs.
    private static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let axApp = WindowAccessibility.application(pid: pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focusedRef = focused,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let window = focusedRef as! AXUIElement
        var winID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &winID) == .success else { return nil }
        return winID
    }
}
