import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct SystemCapabilitiesTests {
    func probe(ax: Bool = true, screen: Bool = true, automation: Bool? = true) -> PermissionProbe {
        PermissionProbe(accessibility: { ax }, screenRecording: { screen }, automation: { _ in automation })
    }

    func capability(_ id: String, _ probe: PermissionProbe) -> FeatureCapability {
        guard let d = ShellDescriptors.all.first(where: { $0.id == id }) else { return .unavailable(reason: "inconnu") }
        return SystemCapabilities.capability(for: d, probe: probe)
    }

    @Test func grantedEverythingIsAvailable() {
        for d in ShellDescriptors.all {
            #expect(SystemCapabilities.capability(for: d, probe: probe()) == .available, "\(d.id)")
        }
    }

    @Test func missingAccessibilityAndScreenRecordingAreReported() {
        #expect(capability("display", probe(ax: false)) == .needsPermission(.accessibility))
        #expect(capability("dock", probe(ax: false)) == .needsPermission(.accessibility))
        #expect(capability("dock", probe(screen: false)) == .needsPermission(.screenRecording))
        #expect(capability("terminal", probe(ax: false, screen: false)) == .available, "needs neither")
    }

    @Test func automationIsReportedOnlyWhenKnownToBeMissing() {
        #expect(capability("finder", probe(automation: false)) == .needsPermission(.automation))
        #expect(capability("nowplaying", probe(automation: false)) == .needsPermission(.automation))
        #expect(capability("finder", probe(automation: nil)) == .available, "unknown is not a refusal")
    }

    @Test func nowPlayingDeclaresAutomation() {
        #expect(ShellDescriptors.all.first { $0.id == "nowplaying" }?.permissions == [.automation])
    }

    @Test func theHubShowsAuthorizeForAMissingPermission() {
        // The registry turns a missing permission into a state the Settings row answers with "Autoriser".
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(
            descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker,
            capabilityProvider: SystemCapabilities.provider(probe(automation: false)))
        #expect(registry.state(for: "nowplaying") == .needsPermission(.automation))
    }

    @Test func theLiveProbeIsCallableWithoutPrompting() {
        // Smoke only: the values depend on the machine, the point is that nothing here can request.
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let defaults = bench.defaults
        let live = PermissionProbe.live(defaults: defaults)
        _ = live.accessibility()
        _ = live.screenRecording()
        #expect(live.automation("nowplaying") == false, "flag unset: not authorized yet")
        defaults.set(true, forKey: "nowplaying.automationRequested")
        #expect(live.automation("nowplaying") == true)
        #expect(live.automation("terminal") == nil)
    }
}
