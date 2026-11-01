import Foundation
import Testing
@testable import PortKit

/// Mac Island has one island: Vorssaint's own stays asleep until a bridge turns the gate on.
@Suite(.serialized) struct IslandGateTests {
    @Test func gateIsOffByDefault() {
        #expect(PortHost.vorssaintIslandEnabled == false)
        #expect(NotchSupport.isEnabled() == false)
    }

    /// With both enable keys on, only the gate (patch 0003) keeps the ported island down: without that clause
    /// `isEnabled` would read true here and this fails. The last assertion proves the keys alone do enable it,
    /// so the gated half cannot pass for another reason.
    @Test func theGateAloneKeepsAnEnabledIslandDown() throws {
        let name = "mis-tests-gate-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }
        suite.set(true, forKey: AppFeature.notch.availabilityKey)
        suite.set(true, forKey: DefaultsKey.notchEnabled)
        #expect(AppFeature.notch.isAvailable(in: suite))

        PortHost.vorssaintIslandEnabled = false
        #expect(NotchSupport.isEnabled(in: suite) == false)
        #expect(NotchSupport.usesHapticFeedback(in: suite) == false)

        PortHost.vorssaintIslandEnabled = true
        defer { PortHost.vorssaintIslandEnabled = false }
        #expect(NotchSupport.isEnabled(in: suite))
    }

    @Test func syncWithPreferencesIsANoOpWhileTheGateIsOff() {
        let service = NotchService.shared
        service.syncWithPreferences()
        #expect(service.running == false)
    }

    @Test @MainActor func installingTheBridgeStartsNothing() {
        PortBridge.install(host: PortBridge.Host(openSettings: {}))
        #expect(PortBridge.vorssaintIslandEnabled == false)
        #expect(PortBridge.registeredPageIDs.isEmpty)
        #expect(NotchService.shared.running == false)
        #expect(appDelegate() != nil)  // the facade is wired, nothing else
    }

    @Test @MainActor func facadeCallsAreNoOpsWithoutAHost() {
        AppDelegate.current = nil
        appDelegate()?.openSettingsWindow()  // nothing to call: must not crash
        let facade = AppDelegate()
        facade.openSettingsWindow()
        facade.closePopover()
        #expect(facade.isOverStatusItem(.zero) == false)
    }

    @Test func nothingElseStartsAtImport() {
        // The registry bridge is only a hook: until a lane sets it, the ported runtime writes nothing for us.
        #expect(PortHostFixture.read { PortHost.setEnabled } == nil)
    }
}
