import Cocoa
import ApplicationServices

enum WindowActions {
    /// Close only the selected CG window. Title matching is deliberately not a
    /// fallback here: duplicate titles must never close a different window.
    static func closeWindow(
        _ entry: WindowEntry,
        windows: (pid_t) -> [AXUIElement]? = windowsForPID,
        windowID: (AXUIElement) -> CGWindowID? = idForWindow,
        pressClose: (AXUIElement) -> Bool = pressCloseButton
    ) -> Bool {
        guard let candidates = windows(entry.pid),
              let target = candidates.first(where: { windowID($0) == entry.cgWindowID }) else {
            return false
        }
        return pressClose(target)
    }

    static func quitApplication(_ entry: WindowEntry) -> Bool {
        guard entry.pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: entry.pid) else { return false }
        return app.terminate()
    }

    private static func windowsForPID(_ pid: pid_t) -> [AXUIElement]? {
        let app = WindowAccessibility.application(pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows { WindowAccessibility.configure(window) }
        return windows
    }

    private static func idForWindow(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success ? id : nil
    }

    private static func pressCloseButton(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let button = value as! AXUIElement
        WindowAccessibility.configure(button)
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }
}

enum SwitcherWindowCommand: Equatable {
    case closeWindow
    case quitApplication
}
