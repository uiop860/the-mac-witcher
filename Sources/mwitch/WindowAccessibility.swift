import ApplicationServices

/// Keep an unresponsive app from consuming the default, multi-second AX wait.
/// This bounds each message, not the total duration of a multi-message operation.
enum WindowAccessibility {
    static let messagingTimeout: Float = 0.25

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        configure(element)
        return element
    }

    static func configure(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }
}
