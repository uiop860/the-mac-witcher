import Cocoa
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var switcher: SwitcherController!
    private var hotkey: HotkeyManager!
    private var launchAtLoginMenuItem: NSMenuItem?

    private static let launchAtLoginFirstRunKey = "mwitch.launchAtLogin.firstRunHandled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        MwitchLog.shared.line("--- launched pid=\(getpid()) bundle=\(Bundle.main.bundlePath) ---")
        MwitchLog.shared.line("AXIsProcessTrusted=\(AXIsProcessTrusted())")
        ensureAccessibility()
        MwitchLog.shared.line("after prompt: AXIsProcessTrusted=\(AXIsProcessTrusted())")
        // Window titles from other apps require Screen Recording on macOS
        // 10.15+ — without it, the enumerator returns 0 windows and Cmd+Tab
        // silently does nothing.
        let scOK = CGPreflightScreenCaptureAccess()
        MwitchLog.shared.line("CGPreflightScreenCaptureAccess=\(scOK)")
        if !scOK { _ = CGRequestScreenCaptureAccess() }
        enableLaunchAtLoginIfFirstRun()
        setupStatusItem()

        WindowRecencyTracker.shared.start()

        switcher = SwitcherController()
        switcher.preWarm()

        hotkey = HotkeyManager()
        hotkey.onPress = { [weak self] in
            self?.switcher.advance()
        }
        hotkey.onShiftPress = { [weak self] in
            self?.switcher.advance(reverse: true)
        }
        hotkey.onWindowCommand = { [weak self] command in
            self?.switcher.performWindowCommand(command) ?? false
        }
        hotkey.onModifiersReleased = { [weak self] in
            self?.switcher.commitIfVisible()
        }
        hotkey.onCancel = { [weak self] in
            guard let self, self.switcher.isVisible else { return false }
            self.switcher.cancel()
            return true
        }
        hotkey.register()
    }

    private func ensureAccessibility() {
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "mwitch")
            btn.image?.isTemplate = true
        }
        let menu = NSMenu()
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)
        self.launchAtLoginMenuItem = loginItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit mwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func enableLaunchAtLoginIfFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.launchAtLoginFirstRunKey) else { return }
        defaults.set(true, forKey: Self.launchAtLoginFirstRunKey)
        do {
            try SMAppService.mainApp.register()
            MwitchLog.shared.line("launch-at-login: enabled by default on first run")
        } catch {
            MwitchLog.shared.line("launch-at-login: register failed: \(error)")
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                launchAtLoginMenuItem?.state = .off
                MwitchLog.shared.line("launch-at-login: disabled")
            } else {
                try service.register()
                launchAtLoginMenuItem?.state = .on
                MwitchLog.shared.line("launch-at-login: enabled")
            }
        } catch {
            MwitchLog.shared.line("launch-at-login: toggle failed: \(error)")
        }
    }

}
