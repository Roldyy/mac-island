import AppKit
import ApplicationServices

/// What the key path asks about the desktop. Not main-actor: the tap thread calls `finderPID`,
/// `focusedApplicationPID` and `isTextEditing`; `isFinderFrontmost` is for the main thread only.
protocol FinderEnvironment: Sendable {
    /// NSWorkspace's frontmost app is Finder. Main thread only; the tap thread reads a snapshot instead.
    func isFinderFrontmost() -> Bool
    func finderPID() -> Int32?
    /// pid of the application that owns the keyboard focus according to Accessibility, nil when unknown.
    func focusedApplicationPID() -> Int32?
    /// True when Finder's focused element is a text field, or when it cannot be told (the key passes).
    func isTextEditing(finderPID: Int32) -> Bool
}

/// Cmd+X / Cmd+V are only ours when Finder is frontmost AND the Accessibility focus is in Finder:
/// a launcher panel that does not activate its app, or Cmd+Tab in flight, fails the second test.
enum FinderFocus {
    static func ownsKeyboard(finderFrontmost: Bool, focusedAppPID: Int32?, finderPID: Int32?) -> Bool {
        guard finderFrontmost, let finderPID, let focusedAppPID else { return false }
        return focusedAppPID == finderPID
    }
}

struct SystemFinderEnvironment: FinderEnvironment {
    func isFinderFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == FinderScripts.finderBundleID
    }

    func finderPID() -> Int32? {
        NSRunningApplication.runningApplications(withBundleIdentifier: FinderScripts.finderBundleID).first?.processIdentifier
    }

    /// Asks the system-wide element for the focused application. No timeout is set here: a messaging
    /// timeout on the system-wide element applies to the whole process (AXUIElement.h) and would cut
    /// every other Accessibility read of the app, the Dock lane's included.
    func focusedApplicationPID() -> Int32? {
        guard AXIsProcessTrusted() else { return nil }
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                                kAXFocusedApplicationAttribute as CFString, &focused)
        guard err == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(focused as! AXUIElement, &pid) == .success else { return nil }
        return pid
    }

    /// Asks Finder's own application element for its focused element, with a timeout set on that
    /// element only. "No focused element" is not editing, any other failure counts as editing.
    func isTextEditing(finderPID: Int32) -> Bool {
        guard AXIsProcessTrusted() else { return true }
        let app = AXUIElementCreateApplication(finderPID)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        switch err {
        case .success:
            guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return true }
            let element = focused as! AXUIElement
            return TextEditingRole.isTextEditing(role: string(element, kAXRoleAttribute),
                                                 subrole: string(element, kAXSubroleAttribute))
        case .noValue, .attributeUnsupported:
            return false
        default:
            return true
        }
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
