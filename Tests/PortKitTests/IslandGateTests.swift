import Foundation
import Testing
@testable import PortKit

/// Mac Island has one island: Vorssaint's own stays asleep until a bridge turns the gate on.
@Suite(.serialized) struct IslandGateTests {
    @Test func gateIsOffByDefault() {
        #expect(PortHost.vorssaintIslandEnabled == false)
        #expect(NotchSupport.isEnabled() == false)
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
        #expect(PortHost.setEnabled == nil)
    }
}
