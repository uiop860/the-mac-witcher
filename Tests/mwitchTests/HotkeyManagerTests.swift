import XCTest
import Carbon.HIToolbox
@testable import mwitch

final class HotkeyManagerTests: XCTestCase {
    func testWindowCommandsRouteOnlyWhenSwitcherHandlesThem() {
        for (key, expected) in [(kVK_ANSI_W, SwitcherWindowCommand.closeWindow),
                                (kVK_ANSI_Q, SwitcherWindowCommand.quitApplication)] {
            let manager = HotkeyManager()
            var visible = false
            var received: [SwitcherWindowCommand] = []
            manager.onWindowCommand = { command in
                guard visible else { return false }
                received.append(command)
                visible = false
                return true
            }
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true)!
            event.flags = [.maskCommand]
            XCTAssertNotNil(manager.handle(type: .keyDown, event: event))
            XCTAssertTrue(received.isEmpty)

            visible = true
            XCTAssertNil(manager.handle(type: .keyDown, event: event))
            XCTAssertEqual(received, [expected])

            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            XCTAssertNil(manager.handle(type: .keyDown, event: event))
            XCTAssertEqual(received, [expected])
            XCTAssertNil(manager.handle(type: .keyUp, event: event))

            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            XCTAssertNotNil(manager.handle(type: .keyDown, event: event))
        }
    }

    func testModifiedOrUnmodifiedWDoesNotTriggerWindowCommand() {
        let manager = HotkeyManager()
        var requests = 0
        manager.onWindowCommand = { _ in requests += 1; return true }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_W), keyDown: true)!
        for flags: CGEventFlags in [[], [.maskCommand, .maskShift],
                                   [.maskCommand, .maskAlternate], [.maskCommand, .maskControl]] {
            event.flags = flags
            XCTAssertNotNil(manager.handle(type: .keyDown, event: event))
        }
        XCTAssertEqual(requests, 0)
    }

    func testHandledWindowCommandStillCommitsOnCommandRelease() {
        let manager = HotkeyManager()
        var commits = 0
        manager.onModifiersReleased = { commits += 1 }
        manager.onWindowCommand = { _ in true }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Tab), keyDown: true)!
        event.flags = [.maskCommand]
        _ = manager.handle(type: .keyDown, event: event)
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_ANSI_W))
        _ = manager.handle(type: .keyDown, event: event)
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Command))
        event.flags = []
        _ = manager.handle(type: .flagsChanged, event: event)
        XCTAssertEqual(commits, 1)
    }

    func testCommandTabMovesDownEvenWithShiftHeld() {
        let manager = HotkeyManager()
        var forward = 0
        var backward = 0
        manager.onPress = { forward += 1 }
        manager.onShiftPress = { backward += 1 }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Tab), keyDown: true)!
        event.flags = [.maskCommand, .maskShift]

        XCTAssertNil(manager.handle(type: .keyDown, event: event))
        XCTAssertEqual(forward, 1)
        XCTAssertEqual(backward, 0)
    }

    func testCommandShiftMovesUpOnPressAndCommitsOnCommandRelease() {
        for shiftKey in [kVK_Shift, kVK_RightShift] {
            let manager = HotkeyManager()
            var backward = 0
            var commits = 0
            manager.onShiftPress = { backward += 1 }
            manager.onModifiersReleased = { commits += 1 }
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(shiftKey), keyDown: true)!
            event.flags = [.maskCommand, .maskShift]

            XCTAssertNil(manager.handle(type: .flagsChanged, event: event))
            XCTAssertEqual(backward, 1)

            event.flags = [.maskCommand]
            _ = manager.handle(type: .flagsChanged, event: event)
            XCTAssertEqual(backward, 1)
            XCTAssertEqual(commits, 0)

            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Command))
            event.flags = []
            _ = manager.handle(type: .flagsChanged, event: event)
            XCTAssertEqual(commits, 1)
        }
    }

    func testShiftWithoutCommandDoesNotNavigate() {
        let manager = HotkeyManager()
        var backward = 0
        manager.onShiftPress = { backward += 1 }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)!
        event.flags = [.maskShift]

        XCTAssertNotNil(manager.handle(type: .flagsChanged, event: event))
        XCTAssertEqual(backward, 0)
    }

    func testCommandReleaseCommitsAfterInterceptedHotkey() {
        var gate = SwitcherCommitGate()

        gate.arm()

        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .commit)
        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .keepWaiting)
    }

    func testUnrelatedModifierReleaseClearsStaleWaitWithoutCommitting() {
        var gate = SwitcherCommitGate()

        gate.arm()

        XCTAssertEqual(
            gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: false),
            .discardStaleWait
        )
        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .keepWaiting)
    }

    func testResetClearsPendingCommit() {
        var gate = SwitcherCommitGate()

        gate.arm()
        gate.reset()

        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .keepWaiting)
    }

    /// Cmd+Tab opens the switcher (arming the gate); Esc cancels it (the tap
    /// resets the gate); the trailing Cmd release must not commit, otherwise the
    /// cancelled switcher would still activate a window.
    func testEscapeCancelDoesNotCommitOnTrailingCommandRelease() {
        var session = SwitcherSession()
        var gate = SwitcherCommitGate()

        // Cmd+Tab intercepted: switcher shows and the commit gate arms.
        let opened = session.start(entries: [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox")
        ])
        gate.arm()
        XCTAssertEqual(opened, .render(scrollTarget: 1))
        XCTAssertTrue(session.isVisible)

        // Esc (still holding Cmd): switcher cancels and the tap clears the gate.
        let cancelled = session.perform(.cancel)
        gate.reset()
        XCTAssertEqual(cancelled, .dismiss(chosen: nil))
        XCTAssertFalse(session.isVisible)

        // Releasing Cmd afterwards is a no-op — no window is activated.
        XCTAssertEqual(
            gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true),
            .keepWaiting
        )
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
