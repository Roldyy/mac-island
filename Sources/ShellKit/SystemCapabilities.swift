import ApplicationServices
import CoreGraphics
import Foundation
import IslandKit

/// Read-only answers to "is this permission granted right now". Every closure is a preflight that
/// never shows a system prompt; a permission with no read-only probe is simply not listed here and
/// counts as granted (the feature's own tab asks for it from a visible button).
public struct PermissionProbe: Sendable {
    public var accessibility: @Sendable () -> Bool
    public var screenRecording: @Sendable () -> Bool
    /// Input Monitoring (`kTCCServiceListenEvent`): the key taps of the Finder feature and of cleaning mode need it
    /// on top of Accessibility. Defaults to granted for callers that do not care.
    public var inputMonitoring: @Sendable () -> Bool
    /// Automation is per target app, so the answer depends on the feature; nil when unknown.
    public var automation: @Sendable (_ featureID: String) -> Bool?
    /// System Audio Recording. macOS has no read call: the answer is the stored outcome of the probe tap a click ran
    /// (`audioCaptureEvidence`), so it reads false until the person pressed "Autoriser". nil = cannot be asked here.
    public var audioCapture: @Sendable () -> Bool?
    /// Notifications (`UNUserNotificationCenter` settings, read from a cache the activation refreshes). nil = unknown.
    public var notifications: @Sendable () -> Bool?

    public init(accessibility: @escaping @Sendable () -> Bool,
                screenRecording: @escaping @Sendable () -> Bool,
                inputMonitoring: @escaping @Sendable () -> Bool = { true },
                automation: @escaping @Sendable (_ featureID: String) -> Bool?,
                audioCapture: @escaping @Sendable () -> Bool? = { nil },
                notifications: @escaping @Sendable () -> Bool? = { nil }) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.inputMonitoring = inputMonitoring
        self.automation = automation
        self.audioCapture = audioCapture
        self.notifications = notifications
    }

    /// Where the mixer stores the status of the last probe tap (a click wrote it). 0 = the tap was created = granted.
    public static let audioCaptureEvidenceKey = "macisland.mixer.audioCaptureProbeStatus"

    /// Pure: what the stored status says. nil when the running bundle cannot ask (no usage description: `swift run`).
    public static func audioCaptureReading(evidence: Int?, hasUsageDescription: Bool) -> Bool? {
        guard hasUsageDescription else { return nil }
        return evidence == 0
    }

    /// The three permissions the monitor watches, read once.
    public func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(accessibility: accessibility(), inputMonitoring: inputMonitoring(),
                           screenRecording: screenRecording())
    }

    /// `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess` and `AEDeterminePermissionToAutomateTarget`
    /// with `askUserIfNeeded: false`. Never `AXIsProcessTrustedWithOptions(prompt)` or a request call.
    public static func live(defaults: UserDefaults) -> PermissionProbe {
        // UserDefaults is thread-safe but not declared Sendable; the closure only reads one Bool.
        nonisolated(unsafe) let defaults = defaults
        return PermissionProbe(
            accessibility: { AXIsProcessTrusted() },
            screenRecording: { CGPreflightScreenCaptureAccess() },
            inputMonitoring: { CGPreflightListenEventAccess() },
            automation: { id in
                switch id {
                case "finder": return finderAutomationGranted()
                // The Now Playing tab queries Spotify and Music only after the user pressed its own
                // "Autoriser"; it records that press under this key and offers no read-only check.
                case "nowplaying": return defaults.bool(forKey: "nowplaying.automationRequested")
                default: return nil
                }
            },
            audioCapture: {
                let described = (Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String ?? "")
                    .isEmpty == false
                return audioCaptureReading(evidence: defaults.object(forKey: audioCaptureEvidenceKey) as? Int,
                                           hasUsageDescription: described)
            },
            notifications: { NotificationAuthorizationCache.shared.granted })
    }

    /// nil when Finder is not running or the state is unreadable: not enough to claim a refusal.
    private static func finderAutomationGranted() -> Bool? {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let desc = target.aeDesc else { return nil }
        switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) {
        case 0: return true
        case -1743, -1744: return false  // refused / would ask
        default: return nil
        }
    }
}

/// Maps a descriptor's permissions to a capability through a probe. Pure given the probe.
public enum SystemCapabilities {
    public static func capability(for descriptor: FeatureDescriptor, probe: PermissionProbe) -> FeatureCapability {
        for permission in descriptor.permissions {
            switch permission {
            case .accessibility where !probe.accessibility():
                return .needsPermission(.accessibility)
            case .screenRecording where !probe.screenRecording():
                return .needsPermission(.screenRecording)
            case .automation where probe.automation(descriptor.id) == false:
                return .needsPermission(.automation)
            case .audioCapture where probe.audioCapture() == false:
                return .needsPermission(.audioCapture)
            case .notifications where probe.notifications() == false:
                return .needsPermission(.notifications)
            default:
                continue
            }
        }
        return .available
    }

    public static func provider(_ probe: PermissionProbe) -> (FeatureDescriptor) -> FeatureCapability {
        { capability(for: $0, probe: probe) }
    }
}
