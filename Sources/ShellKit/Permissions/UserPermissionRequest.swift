import AppKit
import CoreGraphics
import IslandKit

/// What a CLICK on "Autoriser" does. macOS lists an app in Privacy & Security only after the app has asked once:
/// a pane that was merely opened shows no Mac Island row to switch on. The ask happens here, and only here, on a
/// click by the user: the probes (`PermissionProbe`) and the monitor never ask. The matching pane is opened after.
@MainActor
public enum UserPermissionRequest {
    public static func request(_ permission: MonitoredPermission) {
        switch permission {
        case .accessibility:
            // kAXTrustedCheckOptionPrompt is a non-Sendable global in Swift 6: its string value.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        open(permission.settingsURL)
    }

    /// For the feature-level permission enum: asks for the three that need an entry in the list, opens the
    /// pane for every other one.
    public static func request(_ permission: FeaturePermission) {
        if let monitored = MonitoredPermission(permission) {
            request(monitored)
        } else {
            open(permission.settingsURL)
        }
    }

    private static func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }
}
