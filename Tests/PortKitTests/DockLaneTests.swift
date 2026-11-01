import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W3C: Dock Preview and Dock clicks, which replace our `dock` module, bound through a fake runtime and a real
/// `FeatureRegistry`. Nothing here touches an event tap, the Dock, Accessibility or a permission.
@MainActor
@Suite(.serialized) struct DockLaneTests {
    final class Log {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func runtime(_ log: Log) -> DockLane.Runtime {
        DockLane.Runtime(
            migrateLegacySettings: { log.events.append("migrate") },
            syncClick: { log.events.append("click") },
            syncPreview: { log.events.append("preview") },
            stopClick: { log.events.append("click.stop") },
            stopPreview: { log.events.append("preview.stop") },
            restoreAutohide: { log.events.append("restore") },
            watchApp: { log.events.append("watch") },
            unwatchApp: { log.events.append("unwatch") })
    }

    /// The registry as the app builds it: our descriptors plus what the binding adds, the Dock's own descriptor
    /// coming from `ShellDescriptors` (the lane REPLACES the module, it does not add a second switch).
    func rig(switchedOn: Bool = true, accessibility: Bool = true, screenRecording: Bool = true) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        DockLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { accessibility }, screenRecording: { screenRecording },
                                    automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.switches["dock"] = switchedOn
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptor, permission and page tables

    @Test func theDockReplacesOurModuleAndAddsNoDescriptor() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        #expect(r.binding.descriptors.isEmpty, "the registry keeps OUR dock descriptor")
        #expect(ShellDescriptors.all.filter { $0.id == "dock" }.count == 1)
        #expect(r.registry.descriptors.filter { $0.id == "dock" }.count == 1)
        let dock = r.registry.descriptor("dock")
        #expect(dock?.tabID == "dock", "the island tab and the Home tile keep their id")
        #expect(dock?.title == "Dock" && dock?.category == .windows)
        #expect(dock?.permissions == [.accessibility, .screenRecording])
        #expect(dock?.risk == .touchesInput)
        #expect(r.registry.state(for: "dock") == .off)
        #expect(r.log.events.isEmpty, "binding starts nothing")
        #expect(r.binding.pages.isEmpty, "both pages are plain bodies: their catalog rows already carry the dock card")
    }

    @Test func theTwoUpstreamFeaturesAreOneRegistryFeatureWithTheUnionOfTheirPermissions() {
        #expect(AppFeature.dockPreview.registryID == "dock" && AppFeature.dockClick.registryID == "dock")
        #expect(PortFeatureIDs.existing["dockPreview"] == "dock" && PortFeatureIDs.folded["dockClick"] == "dock")
        #expect(Set(AppFeature.dockPreview.permissions) == [.accessibility, .screenRecording])
        #expect(Set(AppFeature.dockClick.permissions) == [.accessibility])
        let shell = Set(ShellDescriptors.all.first { $0.id == "dock" }?.permissions ?? [])
        var union: Set<FeaturePermission> = []
        for feature in [AppFeature.dockPreview, .dockClick] {
            union.formUnion(PortFeatureBinding.featurePermissions(of: feature))
        }
        #expect(shell == union, "our descriptor asks for what the two ported features can use")
        #expect(PortFeatureBinding.risk(of: .dockPreview) == .touchesInput && PortFeatureBinding.risk(of: .dockClick) == .touchesInput)
    }

    @Test func bothPagesCarryTheDockCardAndHaveNoLiveRowsOfTheirOwn() {
        for id in ["dockpreview", "dockclicks"] {
            let page = SettingsPageCatalog.page(id)
            #expect(page?.featureID == "dock", "\(id)")
            #expect(SettingsLive.controls(for: id) == nil, "\(id): the ported body draws the whole page")
        }
        #expect(DockLane.pageIDs == ["dockPreview": "dockpreview", "dockClick": "dockclicks"])
    }

    @Test func bindReplacingTakesTheDockOnceAndNeverTheFoldedFeature() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        #expect(binding.bindReplacing("dockClick", start: {}, stop: {}) == true, "folded: the id is an existing module's")
        let other = PortFeatureBinding(permissions: { PortPermissionState() })
        #expect(other.bindReplacing("dockPreview", start: {}, stop: {}))
        #expect(other.bindReplacing("dockClick", start: {}, stop: {}) == false, "the dock id is already bound")
        #expect(other.bind("dockPreview", start: {}, stop: {}) == nil, "bind() refuses an existing module's id")
        #expect(other.availability("dock") == false, "bound: the registry's verdict, off until started")
    }

    @Test func nothingIsOnAFreshInstallBecauseEveryDockOptionStartsOff() {
        PortHostFixture.isolated { defaults in
            Defaults.register(in: defaults)
            for key in [DefaultsKey.dockPreviewEnabled, DefaultsKey.dockClickMinimize, DefaultsKey.dockClickHide,
                        DefaultsKey.dockClickCycleWindows, DefaultsKey.dockPreviewKeepDockVisible,
                        DefaultsKey.dockPreviewQuitAppOnClose, DefaultsKey.dockPreviewCurrentSpaceOnly] {
                #expect(defaults.bool(forKey: key) == false, "\(key) is off until chosen")
            }
            #expect(defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide) == false, "no journal owed")
            // So switching the registry feature on alone starts services that do nothing (no tap, no panel).
            #expect(DockPreviewSupport.defaultOpenDelayMilliseconds == 200)
        }
    }

    // MARK: Start, stop, kill switch

    @Test func switchingTheDockOnStartsBothServicesOnceAndOffEndsThePreviewFirst() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        r.registry.switches["dock"] = true
        r.registry.switches["dock"] = true
        #expect(r.log.events == ["migrate", "click", "preview", "watch"], "idempotent: one start")
        #expect(r.binding.availability("dock") == true)
        r.log.events.removeAll()
        r.registry.switches["dock"] = false
        #expect(r.log.events == ["unwatch", "preview.stop", "click.stop", "restore"],
                "the hover session ends first (it hands a held Dock auto-hide back), the journal is paid last")
        #expect(r.binding.availability("dock") == false)
        r.registry.switches["dock"] = false
        #expect(r.log.count("preview.stop") == 1, "a second off changes nothing")
    }

    @Test func bothUpstreamFeaturesFollowTheRegistryVerdictNotAStoredKey() {
        PortHostFixture.isolated { defaults in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            defaults.set(true, forKey: AppFeature.dockPreview.availabilityKey)  // a stale stored switch
            #expect(AppFeature.dockPreview.isAvailable == false && AppFeature.dockClick.isAvailable == false)
            r.registry.switches["dock"] = true
            #expect(AppFeature.dockPreview.isAvailable && AppFeature.dockClick.isAvailable, "one switch, both services")
            r.registry.killSwitch = true
            #expect(AppFeature.dockPreview.isAvailable == false && AppFeature.dockClick.isAvailable == false,
                    "so a toggle on a ported page cannot restart a service the registry stopped")
        }
    }

    @Test func killSwitchSafeModeAndQuarantineStopEverythingAndTheFeatureComesBack() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.log.events == ["migrate", "click", "preview", "watch"])
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(r.log.events == ["unwatch", "preview.stop", "click.stop", "restore"], "the kill switch stops all")
        #expect(r.binding.availability("dock") == false)
        r.log.events.removeAll()
        r.registry.killSwitch = false
        #expect(r.log.events == ["migrate", "click", "preview", "watch"])
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.count("preview.stop") == 1 && r.log.count("click.stop") == 1, "safe mode stops the taps too")
        #expect(r.binding.availability("dock") == false)
    }

    @Test func aMissingPermissionStillStartsAndTheGrantRestartsOnceTheRevokeStopsIt() {
        let r = rig(accessibility: false, screenRecording: false)
        defer { r.cleanup() }
        #expect(r.registry.state(for: "dock") == .needsPermission(.accessibility))
        #expect(r.log.events == ["migrate", "click", "preview", "watch"], "the services arm only what is granted")
        let none = PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: false)
        let ax = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false)
        r.log.events.removeAll()
        r.registry.permissionsChanged(PermissionChange(old: none, new: ax))
        #expect(r.log.events == ["unwatch", "preview.stop", "click.stop", "restore",
                                 "migrate", "click", "preview", "watch"], "a grant re-reads both services once")
        r.log.events.removeAll()
        r.registry.permissionsChanged(PermissionChange(old: ax, new: none))
        #expect(r.log.events == ["unwatch", "preview.stop", "click.stop", "restore"], "a revoke removes both taps")
        #expect(r.log.count("preview") == 0, "and nothing restarts while it is missing")
    }

    @Test func quitGivesTheDockBackAndRemovesBothTaps() {
        let log = Log()
        DockLane.quit(runtime: runtime(log))
        #expect(log.events == ["preview.stop", "click.stop", "restore"])
    }

    @Test func theLaneIsInTheLaneListAndTheOldModuleIsNotStartedByTheApp() throws {
        let root = PortSourceScrubTests.repoRoot
        let lanes = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/PortLanes.swift"), encoding: .utf8)
        #expect(lanes.contains("DockLane.bind(into:)"))
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"), encoding: .utf8)
        #expect(!delegate.contains("DockFeature.start") && !delegate.contains("DockFeature.stop"),
                "a registry starter of ours would win over the ported one (`{ _, ours in ours }`)")
        #expect(delegate.contains("DockFeature.tab()"), "the island tab stays")
        let bridge = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/PortBridge.swift"), encoding: .utf8)
        #expect(bridge.contains("DockLane.recoverAtLaunch(defaults: defaults)"), "the autohide journal has a launch caller")
    }

    @Test func ourOldModuleIsGoneAndOnlyTheTabRemains() throws {
        let dir = PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/Features/Dock")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["DockFeature.swift"], "the retired module's controllers, tap and views are deleted")
    }

    @Test func theTabIsStillTheDockTab() {
        let tab = PortDock.tab()
        #expect(tab.id == "dock" && tab.title == "Dock" && tab.systemImage == "dock.rectangle")
    }

    // MARK: The retired module's delay

    @Test func theOldPreviewDelayMovesAcrossOnceAndIsClampedToTheNewRange() {
        PortHostFixture.isolated { defaults in
            #expect(DockLegacySettings.migrateDelay(in: defaults) == nil, "nothing to move: nothing written")
            #expect(defaults.object(forKey: DefaultsKey.dockPreviewOpenDelay) == nil)
            for (old, expected) in [(400, 400), (100, 200), (2000, 900), (850, 850)] {
                defaults.set(old, forKey: DockLegacySettings.oldDelayKey)
                #expect(DockLegacySettings.migrateDelay(in: defaults) == expected, "\(old)")
                #expect(defaults.integer(forKey: DefaultsKey.dockPreviewOpenDelay) == expected)
                #expect(defaults.object(forKey: DockLegacySettings.oldDelayKey) == nil, "the old key goes away")
            }
            #expect(DockLegacySettings.migrateDelay(in: defaults) == nil, "second run: nothing")
        }
    }
}
