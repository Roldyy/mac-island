import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W7C: `appUpdates` and `homebrew` bound through fake runtimes and a real `FeatureRegistry`. Nothing here
/// starts a timer, runs brew or touches the network.
@MainActor
@Suite(.serialized) struct AppUpdatesLaneTests {
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

    func runtime(_ log: Log) -> AppUpdatesLane.Runtime {
        AppUpdatesLane.Runtime(syncUpdates: { log.events.append("updates.sync") },
                               stopUpdates: { log.events.append("updates.stop") },
                               startHomebrew: { log.events.append("brew.start") },
                               stopHomebrew: { log.events.append("brew.stop") })
    }

    func rig(updatesOn: Bool = false, homebrewOn: Bool = false) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        AppUpdatesLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        if updatesOn { registry.switches["appUpdates"] = true }
        if homebrewOn { registry.switches["homebrew"] = true }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptors and pages

    @Test func bothFeaturesAreNewOffByDefaultAndStartNothingWhenBound() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["appUpdates", "homebrew"])
        for id in ["appUpdates", "homebrew"] {
            let d = r.registry.descriptor(id)
            #expect(d != nil, "\(id)")
            #expect(d?.title.isEmpty == false && d?.summary.isEmpty == false, "French title and summary: \(id)")
            #expect(d?.enabledByDefault == false, "\(id)")
            #expect(d?.risk == .touchesSystem, "\(id)")
            #expect(r.registry.state(for: id) == .off, "\(id)")
        }
        #expect(r.log.events.isEmpty, "binding starts nothing, and nothing runs at rest")
    }

    @Test func homebrewNoLongerClaimsAutomationAndUpdatesOnlyAsksForNotifications() {
        // Patch 1552: no Terminal launch and no Finder script, so no Automation row on either feature.
        #expect(PortFeatureBinding.featurePermissions(of: .homebrew) == [])
        #expect(PortFeatureBinding.featurePermissions(of: .uninstaller) == [.fullDiskAccess])
        #expect(PortFeatureBinding.featurePermissions(of: .appUpdates) == [.notifications])
        let r = rig(homebrewOn: true)
        defer { r.cleanup() }
        #expect(r.registry.state(for: "homebrew") == .active, "no Automation consent to wait for")
    }

    @Test func eachFeatureCarriesItsOwnSettingsPage() {
        let r = rig()
        defer { r.cleanup() }
        let pages = r.binding.pages
        #expect(pages.map(\.pageID) == ["appupdates", "homebrew"])
        #expect(pages.map(\.featureID) == ["appUpdates", "homebrew"])
        for id in ["appupdates", "homebrew"] { #expect(SettingsPageCatalog.page(id) != nil, "\(id)") }
    }

    @Test func theLaneIsListedInTheLaunchOrder() throws {
        let lanes = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/PortLanes.swift"),
                               encoding: .utf8)
        #expect(lanes.contains("AppUpdatesLane.bind(into:)"))
    }

    // MARK: Start, stop, kill switch

    @Test func switchingOnStartsOnceAndOffStopsOnce() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["appUpdates"] = true
        r.registry.switches["appUpdates"] = true
        #expect(r.log.events == ["updates.sync"], "one start for two identical switches")
        #expect(r.binding.availability("appUpdates") == true)
        r.registry.switches["appUpdates"] = false
        #expect(r.log.events == ["updates.sync", "updates.stop"])
        #expect(r.binding.availability("appUpdates") == false)
        r.registry.switches["appUpdates"] = false
        #expect(r.log.count("updates.stop") == 1)
    }

    @Test func theKillSwitchStopsBothAndTheyComeBack() {
        let r = rig(updatesOn: true, homebrewOn: true)
        defer { r.cleanup() }
        #expect(r.log.events.sorted() == ["brew.start", "updates.sync"])
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(r.log.events.sorted() == ["brew.stop", "updates.stop"], "the running operation is cancelled")
        #expect(r.binding.availability("appUpdates") == false && r.binding.availability("homebrew") == false)
        r.log.events.removeAll()
        r.registry.killSwitch = false
        #expect(r.log.events.sorted() == ["brew.start", "updates.sync"])
    }

    @Test func safeModeStopsBothBecauseNeitherIsADailyFeature() {
        let r = rig(updatesOn: true, homebrewOn: true)
        defer { r.cleanup() }
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.events.sorted() == ["brew.stop", "updates.stop"])
    }

    @Test func theRegistryVerdictDecidesWhatTheUpdateServiceMayDo() {
        PortHostFixture.isolated { defaults in
            let r = rig()
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            defaults.set(true, forKey: AppFeature.appUpdates.availabilityKey)  // a stale stored switch
            #expect(AppFeature.appUpdates.isAvailable == false, "so `check()` returns before any request")
            r.registry.switches["appUpdates"] = true
            #expect(AppFeature.appUpdates.isAvailable)
            r.registry.killSwitch = true
            #expect(AppFeature.appUpdates.isAvailable == false)
        }
    }
}
