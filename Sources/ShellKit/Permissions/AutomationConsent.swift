import AppKit
import ApplicationServices
import Foundation

/// What macOS answered about "Mac Island may script that app" (Automation is granted per target app).
public enum AutomationConsent: Equatable, Sendable {
    case granted
    /// Refused earlier, or turned off in System Settings: macOS never asks twice, only the pane can change it.
    case denied
    /// The target is not running, so macOS cannot tell and cannot ask.
    case notRunning
    case failed(Int32)

    public init(status: OSStatus) {
        switch status {
        case noErr: self = .granted
        case OSStatus(errAEEventNotPermitted): self = .denied
        case OSStatus(procNotFound): self = .notRunning
        default: self = .failed(status)
        }
    }

    /// `AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded: true`: shows the system prompt when the answer
    /// is still undetermined and BLOCKS until the person answers. Call it off the main thread, from a click only.
    public static let askLive: @Sendable (_ bundleID: String) -> AutomationConsent = { bundleID in
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else { return .failed(-1) }
        return AutomationConsent(status: AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true))
    }
}
