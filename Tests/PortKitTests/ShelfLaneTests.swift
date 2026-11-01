import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W5B: the ported Shelf (which replaces our `shelf` item store) and the ported Scratchpad (a new, off by
/// default feature), bound through fake runtimes and a real `FeatureRegistry`. Nothing here touches a hot key, a
/// mouse monitor, a panel or the real `shelfItems`.
@MainActor
@Suite(.serialized) struct ShelfLaneTests {
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

    func shelfRuntime(_ log: Log) -> ShelfLane.Runtime {
        ShelfLane.Runtime(prepareStore: { log.events.append("prepare") },
                          sync: { log.events.append("sync") },
                          stop: { log.events.append("stop") })
    }

    func scratchpadRuntime(_ log: Log) -> ScratchpadLane.Runtime {
        ScratchpadLane.Runtime(backupLegacyFile: { log.events.append("pad.backup") },
                               sync: { log.events.append("pad.sync") },
                               stop: { log.events.append("pad.stop") })
    }

    /// The registry as the app builds it: our descriptors (the shelf's own comes from `ShellDescriptors`: the lane
    /// REPLACES the module) plus what the binding adds (the scratchpad).
    func rig(shelfOn: Bool = true, scratchpadOn: Bool = false) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        ShelfLane.bind(into: binding, runtime: shelfRuntime(log), scratchpad: scratchpadRuntime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.switches["shelf"] = shelfOn
        if scratchpadOn { registry.switches["scratchpad"] = true }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptor, permission and page tables

    @Test func theShelfReplacesOurModuleAndOnlyTheScratchpadIsAdded() {
        let r = rig(shelfOn: false)
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["scratchpad"], "the registry keeps OUR shelf descriptor")
        #expect(ShellDescriptors.all.filter { $0.id == "shelf" }.count == 1)
        #expect(r.registry.descriptors.filter { $0.id == "shelf" }.count == 1)
        let shelf = r.registry.descriptor("shelf")
        #expect(shelf?.tabID == "shelf", "the island tab and the Home tile keep their id")
        #expect(shelf?.title == "Étagère")
        #expect(shelf?.permissions == [])
        #expect(r.registry.state(for: "shelf") == .off)
        #expect(r.log.events.isEmpty, "binding starts nothing")
        #expect(AppFeature.shelf.registryID == "shelf" && PortFeatureIDs.existing["shelf"] == "shelf")
    }

    @Test func scratchpadIsANewFeatureThatNeedsNoPermissionAndIsOffUntilChosen() {
        let r = rig()
        defer { r.cleanup() }
        let pad = r.registry.descriptor("scratchpad")
        #expect(pad != nil)
        #expect(pad?.id == "scratchpad" && AppFeature.scratchpad.registryID == "scratchpad")
        #expect(pad?.title.isEmpty == false && pad?.summary.isEmpty == false, "French title and summary from the catalog")
        #expect(pad?.permissions == [])
        #expect(pad?.risk == .safe)
        #expect(pad?.enabledByDefault == false)
        #expect(pad?.tabID == nil, "no island tab: it is a floating pad")
        #expect(PortFeatureBinding.featurePermissions(of: .shelf) == [] && PortFeatureBinding.risk(of: .shelf) == .safe)
        #expect(r.registry.state(for: "scratchpad") == .off)
        #expect(r.log.events == ["prepare", "sync"], "only the shelf started; the pad waits for its switch")
    }

    @Test func pagesTwelveAndFiftyThreeAreRealBodies() {
        let r = rig()
        defer { r.cleanup() }
        // Page 12 (Brouillon): bound with the feature, so the page opens with its switch card; the catalog row has none.
        let pages = r.binding.pages
        #expect(pages.map(\.pageID) == ["scratchpad"] && pages.first?.featureID == "scratchpad")
        #expect(SettingsPageCatalog.page("scratchpad")?.featureID == nil)
        #expect(SettingsLive.controls(for: "scratchpad") == nil, "the ported body draws the whole page")
        // Page 53 (Étagère): a plain body, the catalog row already carries the shelf card.
        #expect(SettingsPageCatalog.page("shelf")?.featureID == "shelf")
        #expect(ShelfLane.shelfPageID == "shelf" && ScratchpadLane.pageID == "scratchpad")
        ShelfLane.bind(into: PortFeatureBinding(permissions: { PortPermissionState() }))
        #expect(PortBridge.registeredPageIDs.contains("shelf"))
    }

    @Test func bindReplacingTakesTheShelfOnceAndBindRefusesIt() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        #expect(binding.bindReplacing("shelf", start: {}, stop: {}))
        #expect(binding.bindReplacing("shelf", start: {}, stop: {}) == false, "already bound")
        #expect(binding.bind("shelf", start: {}, stop: {}) == nil, "bind() refuses an existing module's id")
        #expect(binding.availability("shelf") == false, "bound: the registry's verdict, off until started")
        #expect(binding.availability("scratchpad") == nil, "nobody bound the pad here")
    }

    // MARK: Start, stop, kill switch, replacement

    @Test func startImportsOurStoreBeforeTheServiceSyncsAndStopIsIdempotent() {
        let r = rig(shelfOn: false)
        defer { r.cleanup() }
        r.registry.switches["shelf"] = true
        r.registry.switches["shelf"] = true
        #expect(r.log.events == ["prepare", "sync"], "one start, and the import comes first")
        #expect(r.binding.availability("shelf") == true)
        r.log.events.removeAll()
        r.registry.switches["shelf"] = false
        #expect(r.log.events == ["stop"])
        #expect(r.binding.availability("shelf") == false)
        r.registry.switches["shelf"] = false
        #expect(r.log.count("stop") == 1, "a second off changes nothing")
    }

    @Test func killSwitchSafeModeAndQuarantineStopTheShelfAndItComesBack() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.log.events == ["prepare", "sync"])
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(r.log.events == ["stop"], "the kill switch stops the shortcut, the monitors and the panels")
        #expect(r.binding.availability("shelf") == false)
        r.log.events.removeAll()
        r.registry.killSwitch = false
        #expect(r.log.events == ["prepare", "sync"])
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.count("stop") == 0 && r.binding.availability("shelf") == true,
                "safe mode keeps the daily features (the shelf is one) and stops the rest")
    }

    @Test func safeModeStopsTheScratchpadWhichIsNotADailyFeature() {
        let r = rig(scratchpadOn: true)
        defer { r.cleanup() }
        #expect(r.log.count("pad.backup") == 1 && r.log.count("pad.sync") == 1 && r.log.count("sync") == 1)
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.events == ["pad.stop"])
        #expect(r.binding.availability("scratchpad") == false && r.binding.availability("shelf") == true)
    }

    @Test func theRegistryVerdictNotAStoredKeyDecidesWhatTheServiceMayDo() {
        PortHostFixture.isolated { defaults in
            let r = rig(shelfOn: false)
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            defaults.set(true, forKey: AppFeature.shelf.availabilityKey)  // a stale stored switch
            #expect(AppFeature.shelf.isAvailable == false)
            r.registry.switches["shelf"] = true
            #expect(AppFeature.shelf.isAvailable)
            r.registry.killSwitch = true
            #expect(AppFeature.shelf.isAvailable == false,
                    "so a toggle on the ported page cannot restart a service the registry stopped")
        }
    }

    @Test func scratchpadStartsOnlyAfterItsSwitchBacksUpFirstAndStopsClean() {
        let r = rig()
        defer { r.cleanup() }
        r.log.events.removeAll()
        r.registry.switches["scratchpad"] = true
        r.registry.switches["scratchpad"] = true
        #expect(r.log.events == ["pad.backup", "pad.sync"], "the file is copied before the ported store can rewrite it")
        r.log.events.removeAll()
        r.registry.switches["scratchpad"] = false
        #expect(r.log.events == ["pad.stop"])
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(r.log.events == ["stop"], "the pad is already off: only the shelf stops")
        r.registry.killSwitch = false
        r.log.events.removeAll()
        r.registry.switches["scratchpad"] = true
        r.registry.killSwitch = true
        #expect(r.log.events.contains("pad.stop") && r.log.events.contains("stop"))
    }

    // MARK: The wiring around the lane

    @Test func theLaneIsListedTheOldModuleIsGoneAndOnlyTheTabAndDownloadsRemain() throws {
        let root = PortSourceScrubTests.repoRoot
        let lanes = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/PortLanes.swift"), encoding: .utf8)
        #expect(lanes.contains("ShelfLane.bind(into:)"))
        let dir = root.appendingPathComponent("Sources/Features/Shelf")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["DownloadFilter.swift", "DownloadTracker.swift", "DownloadsLister.swift", "DownloadsMonitor.swift",
                          "DownloadsPane.swift", "FileTile.swift", "ShelfFeature.swift", "ShelfModel.swift",
                          "ShelfSettings.swift", "ShelfView.swift"],
                "the item store, the legacy importer, the drop decoder and the old pane are deleted: ONE implementation")
        let feature = try String(contentsOf: dir.appendingPathComponent("ShelfFeature.swift"), encoding: .utf8)
        #expect(feature.contains("PortFeatureBinding.shared.starters[\"shelf\"]?()"),
                "the app delegate's `shelf` starter wins the merge (`{ _, ours in ours }`): it must reach the binding")
        let view = try String(contentsOf: dir.appendingPathComponent("ShelfView.swift"), encoding: .utf8)
        #expect(view.contains("PortShelf.strip()"))
    }

    @Test func theScreenshotLaneNowHostsTheShelf() {
        #expect(ScreenshotShelfBridge.isHosted)
    }

    @Test func noFileOfTheLaneLogsOrReachesTheNetwork() throws {
        let root = PortSourceScrubTests.repoRoot
        let files = ["Sources/PortKit/Bridge/Shelf.swift", "Sources/PortKit/Services/Shelf/ShelfService.swift",
                     "Sources/PortKit/Services/QuickTools/ScratchpadService.swift"]
        for file in files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for token in ["NSLog(", "print(", "URLSession", "os_log", "Logger("] {
                #expect(!text.contains(token), "\(file) must not contain \(token): item names and text never leave the Mac")
            }
        }
    }

    @Test func theIslandTabNeverBuildsTheServiceWhileTheShelfIsOff() throws {
        let text = try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/PortKit/Bridge/Shelf.swift"),
                              encoding: .utf8)
        #expect(text.contains("if AppFeature.shelf.isAvailable, PortHost.defaults.bool(forKey: DefaultsKey.shelfEnabled) {\n            ShelfIslandStrip()"))
        PortHostFixture.isolated { defaults in
            PortHost.availability = { _ in false }
            defaults.set(true, forKey: DefaultsKey.shelfEnabled)
            #expect(LiveShelfDropSink().acceptsDrops == false, "the registry said off")
            PortHost.availability = { _ in true }
            #expect(LiveShelfDropSink().acceptsDrops)
            defaults.set(false, forKey: DefaultsKey.shelfEnabled)
            #expect(LiveShelfDropSink().acceptsDrops == false, "the shelf's own setting is off")
        }
    }
}
