import ApplicationServices
import Foundation
import IslandKit
import Testing
@testable import ShellKit

/// Every permission kind opens ITS pane (the "Autoriser" of the Automation card used to be read as the
/// Accessibility one), and the Automation click asks the target app before it opens anything. Fakes only: no
/// Apple Event, no System Settings.
@MainActor
@Suite(.serialized) struct PrivacyPaneTests {
    static let prefix = "x-apple.systempreferences:com.apple.preference.security?"

    // MARK: The table

    @Test func everyFeaturePermissionMapsToItsOwnAnchor() {
        let expected: [FeaturePermission: String] = [
            .accessibility: "Privacy_Accessibility",
            .automation: "Privacy_Automation",
            .screenRecording: "Privacy_ScreenCapture",
            .microphone: "Privacy_Microphone",
            .camera: "Privacy_Camera",
            .fullDiskAccess: "Privacy_AllFiles",
            .calendar: "Privacy_Calendars",
            .bluetooth: "Privacy_Bluetooth",
            .audioCapture: "Privacy_AudioCapture",
        ]
        for permission in FeaturePermission.allCases {
            if let anchor = expected[permission] {
                #expect(permission.settingsURL?.absoluteString == Self.prefix + anchor, "\(permission)")
                #expect(permission.privacyPane?.rawValue == anchor, "\(permission)")
            } else {
                // Notifications and the system helper live outside Privacy & Security.
                #expect(permission.privacyPane == nil, "\(permission)")
                #expect(permission.settingsURL?.absoluteString.hasPrefix("x-apple.systempreferences:com.apple.") == true)
                #expect(permission.settingsURL?.absoluteString.contains("preference.security") == false, "\(permission)")
            }
        }
    }

    @Test func theMonitoredKindsMapToTheirAnchors() {
        #expect(MonitoredPermission.accessibility.settingsURL?.absoluteString == Self.prefix + "Privacy_Accessibility")
        #expect(MonitoredPermission.inputMonitoring.settingsURL?.absoluteString == Self.prefix + "Privacy_ListenEvent")
        #expect(MonitoredPermission.screenRecording.settingsURL?.absoluteString == Self.prefix + "Privacy_ScreenCapture")
        for permission in MonitoredPermission.allCases {
            #expect(permission.privacyPane.url == permission.settingsURL)
        }
    }

    @Test func noTwoKindsShareAPaneAndTheAutomationOneIsNeverAccessibility() {
        let feature = FeaturePermission.allCases.compactMap(\.privacyPane)
        #expect(Set(feature).count == feature.count, "two permissions on one pane")
        #expect(FeaturePermission.automation.privacyPane == .automation)
        #expect(FeaturePermission.automation.settingsURL != FeaturePermission.accessibility.settingsURL)
        // The same kind reads the same pane through either vocabulary.
        #expect(FeaturePermission.accessibility.privacyPane == MonitoredPermission.accessibility.privacyPane)
        #expect(FeaturePermission.screenRecording.privacyPane == MonitoredPermission.screenRecording.privacyPane)
    }

    @Test func everyPaneLinkIsAValidSecurityDeepLink() {
        for pane in PrivacyPane.allCases {
            #expect(pane.url.absoluteString == Self.prefix + pane.rawValue)
            #expect(pane.rawValue.hasPrefix("Privacy_"))
        }
    }

    // MARK: Automation status codes

    @Test func automationStatusCodesAreMapped() {
        #expect(AutomationConsent(status: noErr) == .granted)
        #expect(AutomationConsent(status: OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(AutomationConsent(status: OSStatus(procNotFound)) == .notRunning)
        #expect(AutomationConsent(status: OSStatus(errAEEventWouldRequireUserConsent)) == .failed(-1744))
    }

    // MARK: The Automation click

    /// Swaps the three hooks for fakes and puts them back.
    private func withFakes(ask: @escaping @Sendable (String) -> AutomationConsent,
                           _ body: (Box<[String]>, Box<[URL]>) async -> Void) async {
        let savedAsk = UserPermissionRequest.automationAsk
        let savedOpen = UserPermissionRequest.openURL
        let savedHandlers = UserPermissionRequest.automationHandlers
        let asked = Box<[String]>([])
        let opened = Box<[URL]>([])
        UserPermissionRequest.automationAsk = { id in asked.value.append(id); return ask(id) }
        UserPermissionRequest.openURL = { opened.value.append($0) }
        UserPermissionRequest.automationHandlers = [:]
        await body(asked, opened)
        UserPermissionRequest.automationAsk = savedAsk
        UserPermissionRequest.openURL = savedOpen
        UserPermissionRequest.automationHandlers = savedHandlers
    }

    @Test func theFinderClickAsksTheFinderAndOpensNothingWhenGranted() async {
        await withFakes(ask: { _ in .granted }) { asked, opened in
            let outcome = await UserPermissionRequest.requestAutomation(featureID: "finder").value
            #expect(outcome == .granted)
            #expect(asked.value == ["com.apple.finder"])
            #expect(opened.value.isEmpty)
        }
    }

    @Test func aRefusedFinderConsentOpensTheAutomationPaneAndNoOther() async {
        await withFakes(ask: { _ in .denied }) { asked, opened in
            let outcome = await UserPermissionRequest.requestAutomation(featureID: "finder").value
            #expect(outcome == .openedPane)
            #expect(asked.value == ["com.apple.finder"])
            #expect(opened.value.map(\.absoluteString) == [Self.prefix + "Privacy_Automation"])
        }
    }

    @Test func anUnreadableAnswerAlsoSendsThePersonToThePane() async {
        for answer in [AutomationConsent.notRunning, .failed(-50)] {
            await withFakes(ask: { _ in answer }) { _, opened in
                _ = await UserPermissionRequest.requestAutomation(featureID: "finder").value
                #expect(opened.value.map(\.absoluteString) == [Self.prefix + "Privacy_Automation"], "\(answer)")
            }
        }
    }

    @Test func aFeatureWithNoKnownTargetOpensThePaneWithoutAsking() async {
        await withFakes(ask: { _ in .granted }) { asked, opened in
            for id in [nil, "nowplaying", "unknown"] as [String?] {
                let outcome = await UserPermissionRequest.requestAutomation(featureID: id).value
                #expect(outcome == .openedPane, "\(String(describing: id))")
            }
            #expect(asked.value.isEmpty, "nothing is asked for a target nobody named")
            #expect(opened.value.count == 3)
            #expect(opened.value.allSatisfy { $0.absoluteString == Self.prefix + "Privacy_Automation" })
        }
    }

    @Test func aFeatureHandlerTakesTheClickInsteadOfTheGenericAsk() async {
        await withFakes(ask: { _ in .granted }) { asked, opened in
            var handled = 0
            UserPermissionRequest.automationHandlers["nowplaying"] = { handled += 1 }
            let outcome = await UserPermissionRequest.requestAutomation(featureID: "nowplaying").value
            #expect(outcome == .handled && handled == 1)
            #expect(asked.value.isEmpty && opened.value.isEmpty)
        }
    }

    @Test func theCardRereadsItsStateOnceMacOSAnswered() async {
        await withFakes(ask: { _ in .granted }) { _, _ in
            var seen: [UserPermissionRequest.AutomationOutcome] = []
            let task = UserPermissionRequest.requestAutomation(featureID: "finder") { seen.append($0) }
            _ = await task.value
            #expect(seen == [.granted])
        }
    }

    @Test func theFinderAndNowPlayingDescriptorsAskForAutomationThroughTheseTargets() {
        let wanting = ShellDescriptors.all.filter { $0.permissions.contains(.automation) }.map(\.id)
        #expect(Set(wanting) == ["finder", "nowplaying"])
        #expect(UserPermissionRequest.automationTargets["finder"] == "com.apple.finder")
    }
}

/// A `@Sendable` box for fake hooks (the ask runs off the main actor).
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
