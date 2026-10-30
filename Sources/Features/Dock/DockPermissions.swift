import ApplicationServices
import CoreGraphics

@MainActor protocol DockPermissionChecking: AnyObject {
    var accessibilityGranted: Bool { get }
    var screenRecordingGranted: Bool { get }
    /// Shows the system prompt. Only ever called from a button click.
    func requestAccessibility()
    /// Shows the system prompt. Only ever called from a button click.
    func requestScreenRecording()
}

enum PermissionLines {
    static func accessibility(granted: Bool) -> String {
        granted ? "Accessibility: granted"
            : "Accessibility is needed to read the Dock and the app windows."
    }
    static func screenRecording(granted: Bool) -> String {
        granted ? "Screen Recording: granted"
            : "Screen Recording is needed for window thumbnails."
    }
}

@MainActor
final class SystemPermissions: DockPermissionChecking {
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" // kAXTrustedCheckOptionPrompt, a non-Sendable global in Swift 6
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }
}
