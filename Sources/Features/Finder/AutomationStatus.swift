import AppKit
import ApplicationServices

enum AutomationStatus: Equatable {
    case granted, denied, notDetermined, finderNotRunning, unknown

    init(osStatus: OSStatus) {
        switch osStatus {
        case 0: self = .granted
        case -1743: self = .denied                 // errAEEventNotPermitted
        case -1744: self = .notDetermined          // errAEEventWouldRequireUserConsent
        case -600: self = .finderNotRunning        // procNotFound
        default: self = .unknown
        }
    }
}

enum AutomationPermission {
    /// `ask: false` only reads the state; `ask: true` shows the system prompt and must come from a button.
    /// Blocks while the prompt is up: call it off the main thread.
    static func status(ask: Bool) -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: FinderScripts.finderBundleID)
        guard let desc = target.aeDesc else { return .unknown }
        let code = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        return AutomationStatus(osStatus: code)
    }
}
