import AppKit
import ApplicationServices

/// What the tap asks about the desktop right now. Main thread only.
@MainActor
protocol FinderEnvironment {
    func isFinderFrontmost() -> Bool
    func isTextEditing() -> Bool
}

@MainActor
struct SystemFinderEnvironment: FinderEnvironment {
    func isFinderFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == FinderScripts.finderBundleID
    }

    /// Asks Accessibility for the focused element. A short timeout keeps the tap callback fast;
    /// "no focused element" is not editing, any other failure counts as editing (the key passes).
    func isTextEditing() -> Bool {
        guard AXIsProcessTrusted() else { return true }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
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
