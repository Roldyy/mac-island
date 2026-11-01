import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W2B: the mixer (which replaces our `audio` module), the output switcher and the device priority, bound
/// through a fake runtime and a real `FeatureRegistry`. Nothing here touches Core Audio, a tap or a permission.
@MainActor
@Suite(.serialized) struct MixerLaneTests {
    final class Log {
        var events: [String] = []
        /// A sweep that finishes only when the test says so.
        var pendingSweep: (@MainActor () -> Void)?
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func runtime(_ log: Log, deferSweep: Bool = false) -> MixerLane.Runtime {
        MixerLane.Runtime(
            sweepStaleAggregates: { done in
                log.events.append("sweep")
                if deferSweep { log.pendingSweep = done } else { done() }
            },
            migrateLegacySettings: { log.events.append("migrate") },
            syncRoller: { log.events.append("roller") },
            syncMixer: { log.events.append("mixer") },
            syncInput: { log.events.append("input") },
            syncSwitcher: { log.events.append("switcher") },
            stopSwitcher: { log.events.append("switcher.stop") },
            syncPriority: { log.events.append("priority") },
            stopAllTaps: { log.events.append("taps.stop") },
            watchApp: { log.events.append("watch") },
            unwatchApp: { log.events.append("unwatch") })
    }

    /// The registry as the app builds it: our descriptors plus what the binding adds, the mixer's own `audio`
    /// descriptor coming from `ShellDescriptors` (the lane REPLACES the module, it does not add a second switch).
    func rig(switchedOn: Bool = true, deferSweep: Bool = false) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })  // nothing granted: audio needs none
        let log = Log()
        MixerLane.bind(into: binding, runtime: runtime(log, deferSweep: deferSweep))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { false }, screenRecording: { false }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        for id in ["audio", "soundOutputSwitcher", "audioPriority"] { registry.switches[id] = switchedOn }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptors and pages

    @Test func theMixerReplacesOurModuleAndTheOtherTwoAreNewDescriptors() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        // No second `audio` descriptor: the registry keeps ours (title, island tab, migrated switch).
        #expect(r.binding.descriptors.map(\.id) == ["soundOutputSwitcher", "audioPriority"])
        #expect(ShellDescriptors.all.filter { $0.id == "audio" }.count == 1)
        #expect(r.registry.descriptors.filter { $0.id == "audio" }.count == 1)
        #expect(r.registry.descriptor("audio")?.tabID == "audio")
        for d in r.binding.descriptors {
            #expect(d.enabledByDefault == false, "\(d.id) is off until the user chooses it")
            #expect(d.category == .sound && d.permissions.isEmpty && d.risk == .touchesSystem, "\(d.id)")
            #expect(r.registry.state(for: d.id) == .off)
        }
        #expect(r.log.events.isEmpty, "binding starts nothing")
    }

    @Test func threePagesCarryTheThreeFeaturesAndTheCatalogRowsHaveNoFeatureCard() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        let pages = Dictionary(uniqueKeysWithValues: r.binding.pages.map { ($0.featureID, $0.pageID) })
        #expect(pages == ["audio": "mixer", "soundOutputSwitcher": "outputswitch", "audioPriority": "audiopriority"])
        for page in r.binding.pages {
            let row = SettingsPageCatalog.page(page.pageID)
            #expect(row != nil, "\(page.pageID)")
            // The page body opens with its own status card, so the catalog row must not add a second one.
            #expect(row?.featureID == nil, "\(page.pageID) would show two status cards")
        }
        #expect(MixerLane.pageIDs == ["mixer": "mixer", "soundOutputSwitcher": "outputswitch",
                                       "audioPriority": "audiopriority"])
    }

    @Test func bindReplacingOnlyTakesAnExistingModuleOnce() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        #expect(binding.bindReplacing("scrollInverter", start: {}, stop: {}) == false, "new to Mac Island: bind() owns it")
        #expect(binding.bindReplacing("noSuchFeature", start: {}, stop: {}) == false)
        #expect(binding.bindReplacing("mixer", start: {}, stop: {}))
        #expect(binding.bindReplacing("mixer", start: {}, stop: {}) == false, "bound twice")
        #expect(binding.descriptors.isEmpty, "no descriptor for a replaced module")
        #expect(binding.availability("audio") == false, "bound: the registry's verdict, off until started")
        #expect(binding.bind("mixer", start: {}, stop: {}) == nil, "bind() still refuses an existing module's id")
    }

    // MARK: Start, stop, kill switch

    @Test func switchingTheMixerOnSweepsThenStartsThreeServicesOnceAndOffTearsTapsDownFirst() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        r.registry.switches["audio"] = true
        r.registry.switches["audio"] = true
        #expect(r.log.events == ["migrate", "sweep", "roller", "mixer", "input", "watch"])
        #expect(r.binding.availability("audio") == true)
        r.log.events.removeAll()
        r.registry.switches["audio"] = false
        #expect(r.log.events == ["unwatch", "taps.stop", "roller", "mixer", "input"],
                "taps go first, then the services re-read a mixer that is no longer available")
        #expect(r.binding.availability("audio") == false)
    }

    @Test func theMixerStartsWithNoPermissionGrantedBecauseTapsWaitForTheClick() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.registry.state(for: "audio") == .active, "audioCapture has no read-only probe: the click decides")
        #expect(r.log.events.contains("mixer"))
    }

    @Test func aFeatureSwitchedOffDuringTheSweepStaysOff() {
        let r = rig(switchedOn: false, deferSweep: true)
        defer { r.cleanup() }
        r.registry.switches["audio"] = true
        #expect(r.log.events == ["migrate", "sweep"], "nothing starts before the sweep ends")
        r.registry.switches["audio"] = false
        r.log.events.removeAll()
        r.log.pendingSweep?()
        #expect(r.log.events.isEmpty, "the stopped mixer is not started by a late sweep")
    }

    @Test func switcherAndPriorityStartAndStopThroughTheSharedDeviceWatch() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        r.registry.switches["soundOutputSwitcher"] = true
        #expect(r.log.events == ["mixer", "switcher"])
        r.registry.switches["soundOutputSwitcher"] = false
        #expect(r.log.events == ["mixer", "switcher", "switcher.stop", "mixer"])
        r.log.events.removeAll()
        r.registry.switches["audioPriority"] = true
        #expect(r.log.events == ["mixer", "input", "priority"])
        r.registry.switches["audioPriority"] = false
        #expect(r.log.events == ["mixer", "input", "priority", "priority", "input", "mixer"])
    }

    @Test func killSwitchStopsAllThreeAndSafeModeKeepsNone() {
        let r = rig()
        defer { r.cleanup() }
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(r.log.events.contains("taps.stop") && r.log.events.contains("switcher.stop"))
        for id in ["audio", "soundOutputSwitcher", "audioPriority"] {
            #expect(r.binding.availability(id) == false, "\(id) reads unavailable, so a page toggle cannot restart it")
        }
        r.log.events.removeAll()
        r.registry.killSwitch = false
        #expect(r.log.events.contains("sweep") && r.log.events.contains("switcher") && r.log.events.contains("priority"))
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.events.contains("taps.stop"), "safe mode stops the taps too")
        #expect(r.binding.availability("audio") == false)
    }

    @Test func stoppingOneFeatureLeavesTheOthersAlone() {
        let r = rig()
        defer { r.cleanup() }
        r.log.events.removeAll()
        r.registry.switches["audioPriority"] = false
        #expect(!r.log.events.contains("taps.stop"), "turning the priority off never drops the per-app taps")
        #expect(r.binding.availability("audio") == true)
        #expect(r.binding.availability("soundOutputSwitcher") == true)
    }
}
