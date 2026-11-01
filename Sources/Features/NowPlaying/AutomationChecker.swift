import AppKit
import ApplicationServices
import Foundation

/// Where the macOS Automation permission of one player stands.
enum AutomationStatus: Equatable, Sendable {
    case granted
    /// The user refused it (or turned it off in System Settings).
    case denied
    /// Never asked: only a user click may ask.
    case notAsked
    /// The player is not open: macOS cannot tell.
    case notRunning
    case unknown
    /// macOS answered with a code this app does not map (the number is shown on the card and logged).
    case failed(Int)
}

/// Reads (and, on a click only, asks for) the Automation permission "Mac Island -> player".
protocol AutomationChecking: Sendable {
    /// `askUser` true may show the system prompt and BLOCKS until the user answers: call it off the main thread,
    /// and only from a button the user pressed.
    func status(bundleID: String, askUser: Bool) -> AutomationStatus
}

struct LiveAutomationChecker: AutomationChecking {
    init() {}

    func status(bundleID: String, askUser: Bool) -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown }
        let result = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, askUser)
        switch Int(result) {
        case Int(noErr): return .granted
        case Int(errAEEventNotPermitted): return .denied
        case Int(errAEEventWouldRequireUserConsent): return .notAsked
        case Int(procNotFound): return .notRunning
        default: return .failed(Int(result))
        }
    }
}

/// Where the user turns the permission back on once they refused it.
enum AutomationPane {
    static let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
}
