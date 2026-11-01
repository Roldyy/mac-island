import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// `PortFeatureBinding` against a real `FeatureRegistry`, a fake runtime and a fake permission state: descriptors,
/// the off-by-default rule, the permission gate, idempotence, the kill switch, safe mode and the availability hook.
/// Nothing here starts a real service, taps an event or asks for a permission.
@MainActor
@Suite(.serialized) struct PortFeatureBindingTests {
    final class Runtime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let runtime: Runtime
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    /// `granted` is what the fake system answers; `switchedOn` flips every bound feature on before launch.
    func rig(_ features: [AppFeature] = [.scrollInverter, .smoothScroll, .urlCleaner],
             granted: PortPermissionState = PortPermissionState(accessibility: true),
             switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let runtime = Runtime()
        for feature in features {
            let id = feature.registryID
            binding.bind(feature, start: { runtime.events.append("start \(id)") }, stop: { runtime.events.append("stop \(id)") })
        }
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { permissions.value.screenRecording },
                                    inputMonitoring: { permissions.value.inputMonitoring }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, runtime: runtime, permissions: permissions,
                   cleanup: { bench.cleanup(); marker.clear() })
    }

    func change(_ rig: Rig, to new: PortPermissionState) {
        let old = rig.permissions.value
        rig.permissions.value = new
        rig.registry.permissionsChanged(PermissionChange(
            old: PermissionSnapshot(accessibility: old.accessibility, inputMonitoring: old.inputMonitoring,
                                    screenRecording: old.screenRecording),
            new: PermissionSnapshot(accessibility: new.accessibility, inputMonitoring: new.inputMonitoring,
                                    screenRecording: new.screenRecording)))
    }

    // MARK: Descriptors

    @Test func descriptorsComeFromTheCatalogInFrench() {
        let scroll = PortFeatureBinding.descriptor(for: .scrollInverter)
        #expect(scroll.id == "scrollInverter")
        #expect(scroll.title == "Inverser le défilement de la souris")
        #expect(scroll.summary == "Inverse le sens de la molette de la souris")
        #expect(scroll.category == .input)
        #expect(scroll.permissions == [.accessibility])
        #expect(scroll.risk == .touchesInput)
        #expect(scroll.enabledByDefault == false)
        #expect(scroll.systemImage == AppFeature.scrollInverter.symbolName)

        let cleaner = PortFeatureBinding.descriptor(for: .urlCleaner)
        #expect(cleaner.id == "urlCleaner" && cleaner.title == "Nettoyer l’URL")
        #expect(cleaner.category == .files && cleaner.permissions.isEmpty && cleaner.risk == .safe)
    }

    @Test func everyFeatureYieldsADescriptorThatIsOffByDefaultWithTextAndAKnownCategory() {
        for feature in AppFeature.allCases {
            let d = PortFeatureBinding.descriptor(for: feature)
            #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(feature.rawValue)")
            #expect(d.enabledByDefault == false, "\(feature.rawValue)")
            #expect(d.id == feature.registryID)
            #expect(Set(d.permissions).count == d.permissions.count, "no duplicate permission: \(feature.rawValue)")
        }
    }

    @Test func theMonitoredPermissionTableMatchesTheCatalogForTheWaveOneIds() {
        for id in PortedPermissionTable.ids {
            guard let feature = AppFeature(rawValue: id) else { Issue.record("\(id) is not an upstream feature"); continue }
            let d = PortFeatureBinding.descriptor(for: feature)
            let fromCatalog = Set(d.permissions.compactMap(MonitoredPermission.init))
            #expect(MonitoredPermission.portedFeaturePermissions[id] == fromCatalog, "\(id)")
            #expect(MonitoredPermission.used(by: d) == fromCatalog, "\(id)")
        }
    }

    @Test func bindingRefusesWhatItDoesNotOwn() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        #expect(binding.bind("noSuchFeature", start: {}, stop: {}) == nil)
        #expect(binding.bind("shelf", start: {}, stop: {}) == nil, "our own module owns that switch")
        #expect(binding.bind("keepAwake", start: {}, stop: {}) == nil)
        #expect(binding.bind("urlCleaner", start: {}, stop: {}) != nil)
        #expect(binding.bind("urlCleaner", start: {}, stop: {}) == nil, "bound once")
        #expect(binding.descriptors.map(\.id) == ["urlCleaner"])
    }

    // MARK: Off by default

    @Test func everyBoundFeatureIsOffAndNothingStartsUntilTheSwitchIsOn() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        #expect(r.runtime.events.isEmpty)
        for d in r.binding.descriptors { #expect(r.registry.state(for: d.id) == .off, "\(d.id)") }
        r.registry.switches["urlCleaner"] = true
        #expect(r.runtime.events == ["start urlCleaner"])
    }

    @Test func aMigratedSwitchTurnsTheFeatureOnAtLaunchOnlyWhenPermissionsAreGranted() {
        // `shell.enabled.<id>` is what the migrator copies from `featureAvailable.<id>`.
        let permissions = Box(PortPermissionState())
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let runtime = Runtime()
        binding.bind(.scrollInverter, start: { runtime.events.append("start") }, stop: { runtime.events.append("stop") })
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(true, forKey: "shell.enabled.scrollInverter")
        let registry = FeatureRegistry(
            descriptors: binding.descriptors, defaults: bench.defaults,
            crashMarker: CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mis-test-marker-\(UUID().uuidString)")),
            capabilityProvider: { _ in .needsPermission(.accessibility) }, withdraw: { _ in })
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        #expect(registry.state(for: "scrollInverter") == .needsPermission(.accessibility))
        #expect(runtime.events.isEmpty, "switched on but not granted: the upstream start never ran")
    }

    // MARK: Permission gate

    @Test func startNeverRunsWhileAPermissionIsMissingAndRunsOnceItIsGranted() {
        let r = rig(granted: PortPermissionState())
        defer { r.cleanup() }
        #expect(r.runtime.count("start scrollInverter") == 0)
        #expect(r.runtime.count("start smoothScroll") == 0)
        #expect(r.runtime.count("start urlCleaner") == 1, "needs no permission")
        change(r, to: PortPermissionState(accessibility: true))
        #expect(r.runtime.count("start scrollInverter") == 1)
        #expect(r.runtime.count("start smoothScroll") == 1)
        #expect(r.runtime.count("start urlCleaner") == 1, "a grant does not touch a feature that does not use it")
        change(r, to: PortPermissionState(accessibility: true, screenRecording: true))
        #expect(r.runtime.count("start scrollInverter") == 1, "an unrelated grant restarts nothing")
    }

    @Test func aRevokeStopsTheFeatureAndTheNextGrantStartsItAgain() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.runtime.count("start scrollInverter") == 1)
        change(r, to: PortPermissionState())
        #expect(r.runtime.count("stop scrollInverter") == 1)
        #expect(r.runtime.count("stop urlCleaner") == 0)
        change(r, to: PortPermissionState(accessibility: true))
        #expect(r.runtime.count("start scrollInverter") == 2)
    }

    @Test func startIsIdempotentAndStopAlwaysReachesTheUpstreamStop() {
        let r = rig()
        defer { r.cleanup() }
        let start = r.binding.starters["urlCleaner"]!
        let stop = r.binding.stoppers["urlCleaner"]!
        start(); start()
        #expect(r.runtime.count("start urlCleaner") == 1)
        stop(); stop()
        #expect(r.runtime.count("stop urlCleaner") == 2, "the upstream stops are idempotent: always forwarded")
        start()
        #expect(r.runtime.count("start urlCleaner") == 2)
    }

    @Test func permissionFreeBindingNeverReadsThePermissionsItDoesNotNeed() {
        let reads = Box(0)
        let binding = PortFeatureBinding(permissions: { reads.value += 1; return PortPermissionState() })
        let runtime = Runtime()
        binding.bind(.urlCleaner, start: { runtime.events.append("start") }, stop: {})
        binding.starters["urlCleaner"]!()
        #expect(runtime.events == ["start"])
        #expect(reads.value == 0)
    }

    // MARK: Kill switch and safe mode

    @Test func theKillSwitchCallsEveryBoundStop() {
        let r = rig()
        defer { r.cleanup() }
        #expect(Set(r.runtime.events) == ["start scrollInverter", "start smoothScroll", "start urlCleaner"])
        r.registry.killSwitch = true
        for d in r.binding.descriptors {
            #expect(r.runtime.count("stop \(d.id)") == 1, "\(d.id) was not stopped by the kill switch")
            #expect(r.registry.state(for: d.id) == .killed)
        }
        r.registry.killSwitch = false
        for d in r.binding.descriptors { #expect(r.runtime.count("start \(d.id)") == 2, "\(d.id) restarts") }
    }

    @Test func theKillSwitchStopsEvenAFeatureWhosePermissionWasNeverGranted() {
        let r = rig(granted: PortPermissionState())
        defer { r.cleanup() }
        r.registry.killSwitch = true
        #expect(r.runtime.count("stop scrollInverter") == 1, "the registry thinks it runs; the upstream stop is harmless")
        #expect(r.runtime.count("start scrollInverter") == 0)
    }

    @Test func safeModeStopsThePortedFeatures() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.safeMode = true
        for d in r.binding.descriptors { #expect(r.runtime.count("stop \(d.id)") == 1, "\(d.id)") }
    }

    @Test func aSwitchOffStopsOnlyThatFeature() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["smoothScroll"] = false
        #expect(r.runtime.count("stop smoothScroll") == 1)
        #expect(r.runtime.count("stop scrollInverter") == 0 && r.runtime.count("stop urlCleaner") == 0)
    }

    // MARK: Availability hook

    @Test func theAvailabilityHookFollowsTheRegistryNotTheStoredKey() {
        PortHostFixture.isolated { defaults in
            let r = rig()
            defer { r.cleanup() }
            r.binding.connectAvailability()
            #expect(AppFeature.urlCleaner.isAvailable)
            #expect(AppFeature.scrollInverter.isAvailable)
            #expect(PortHost.availability?("shelf") == nil, "nobody bound shelf here")
            #expect(r.binding.availability("urlCleaner") == true && r.binding.availability("nothing") == nil)

            r.registry.killSwitch = true
            #expect(!AppFeature.urlCleaner.isAvailable, "a toggle on a ported page cannot restart what the kill switch stopped")
            #expect(!AppFeature.scrollInverter.isAvailable)
            #expect(defaults.object(forKey: AppFeature.urlCleaner.availabilityKey) == nil, "no key was written")
            r.registry.killSwitch = false
            #expect(AppFeature.urlCleaner.isAvailable)
            r.registry.switches["urlCleaner"] = false
            #expect(!AppFeature.urlCleaner.isAvailable)
        }
    }

    // MARK: Pages

    @Test func aPageBodyIsOfferedWithItsFeatureAndReadsTheHostsDefaults() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        binding.bind(.urlCleaner, page: PortFeaturePage(pageID: "urlcleaner") { AnyView(Text("corps")) },
                     start: {}, stop: {})
        binding.bind(.scrollInverter, start: {}, stop: {})
        let pages = binding.pages
        #expect(pages.map(\.pageID) == ["urlcleaner"])
        #expect(pages.first?.featureID == "urlCleaner")
    }
}

/// The ids of the first input wave, in the one place both the table test and the binding tests read.
enum PortedPermissionTable {
    static let ids = [
        "scrollInverter", "scrollHorizontal", "smoothScroll", "linearScroll", "mouseAcceleration", "mouseNavigation",
        "mouseButtonShortcuts", "middleClick", "mouseClickDebounce", "focusFollowsMouse", "keyboardDebounce",
        "superKey", "quitWindowProtection", "textSnippets", "cleaningMode",
    ]
}
