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

    /// System Audio Recording has no read-only probe and no request call: the only way to make macOS list the app
    /// and ask is to create a process tap, which lives in the mixer (PortKit, `MixerAudioCapture.requestByClick`).
    /// The app delegate plugs it in here, so ShellKit stays free of PortKit and the tap exists in ONE place. The
    /// handler runs only from this click path, behind the mixer's own feature switch, and opens the pane itself
    /// when the system refuses. Unset (tests, a build without the mixer): the pane opens and nothing is asked.
    @MainActor public static var audioCaptureRequest: (@MainActor () -> Void)?

    /// For the feature-level permission enum: asks for the three that need an entry in the list, asks System Audio
    /// Recording through `audioCaptureRequest`, opens the pane for every other one.
    public static func request(_ permission: FeaturePermission) {
        if let monitored = MonitoredPermission(permission) {
            request(monitored)
        } else if permission == .audioCapture, let ask = audioCaptureRequest {
            ask()
        } else {
            open(permission.settingsURL)
        }
    }

    // MARK: Automation

    /// The app each feature scripts, by registry id. A feature that is not listed has its own ask
    /// (`automationHandlers`) or only gets the pane.
    public static let automationTargets: [String: String] = ["finder": "com.apple.finder"]

    /// A feature whose Automation ask is its own (several targets, its own state): the app delegate plugs it in
    /// and this click runs it instead of the generic ask. Runs from the click only.
    @MainActor public static var automationHandlers: [String: @MainActor () -> Void] = [:]

    /// The blocking ask (live: `AutomationConsent.askLive`). Tests swap it.
    @MainActor public static var automationAsk: @Sendable (String) -> AutomationConsent = AutomationConsent.askLive

    /// Opens a pane (live: Launch Services). Tests swap it.
    @MainActor public static var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }

    public enum AutomationOutcome: Equatable, Sendable {
        /// A feature-specific handler took the click.
        case handled
        /// macOS answered "granted" (the person said yes now, or it already was).
        case granted
        /// Refused or unreadable: the Automation pane was opened.
        case openedPane
    }

    /// The "Autoriser" click of an Automation card. Asks macOS for the consent of the feature's target app
    /// (`AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded`, off the main thread: the call blocks while
    /// the system prompt is up). When the answer is not "granted", the Automation pane opens, because macOS never
    /// asks twice. `afterAnswer` runs on the main actor with the outcome (the card re-reads its state there).
    /// No known target: the pane opens and nothing is asked.
    @MainActor @discardableResult
    public static func requestAutomation(featureID: String?,
                                         afterAnswer: (@MainActor (AutomationOutcome) -> Void)? = nil) -> Task<AutomationOutcome, Never> {
        if let featureID, let handler = automationHandlers[featureID] {
            handler()
            afterAnswer?(.handled)
            return Task { .handled }
        }
        guard let featureID, let bundleID = automationTargets[featureID] else {
            openURL(PrivacyPane.automation.url)
            afterAnswer?(.openedPane)
            return Task { .openedPane }
        }
        let ask = automationAsk
        return Task { @MainActor in
            let consent = await Task.detached { ask(bundleID) }.value
            let outcome: AutomationOutcome
            if consent == .granted {
                outcome = .granted
            } else {
                openURL(PrivacyPane.automation.url)
                outcome = .openedPane
            }
            afterAnswer?(outcome)
            return outcome
        }
    }

    private static func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }
}
