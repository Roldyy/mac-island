import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W4-D: `mediaTools` and `wallpaper` bound through a fake runtime and a real `FeatureRegistry`. Nothing here
/// starts a converter, touches the wallpaper, asks for a permission or opens a window.
@MainActor
@Suite(.serialized) struct MediaToolsLaneTests {
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

    func runtime(_ log: Log) -> MediaToolsLane.Runtime {
        MediaToolsLane.Runtime(
            startMedia: { log.events.append("media.start") },
            stopMedia: { log.events.append("media.stop") },
            startWallpaper: { log.events.append("wallpaper.start") },
            stopWallpaper: { log.events.append("wallpaper.stop") })
    }

    /// The registry as the app builds it: our descriptors plus what the binding adds.
    func rig(media: Bool = false, wallpaper: Bool = false) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        MediaToolsLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        // No permission is granted at all: neither feature may need one.
        let probe = PermissionProbe(accessibility: { false }, screenRecording: { false }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.switches["mediaTools"] = media
        registry.switches["wallpaper"] = wallpaper
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptor, permission and page tables

    @Test func bothFeaturesGetADescriptorOffByDefaultWithNoPermission() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["mediaTools", "wallpaper"])
        for descriptor in r.binding.descriptors {
            #expect(descriptor.enabledByDefault == false, "\(descriptor.id)")
            #expect(descriptor.permissions.isEmpty, "\(descriptor.id): no permission, so no prompt and no gate")
            #expect(descriptor.category == .tools && descriptor.tabID == nil)
            #expect(!descriptor.title.isEmpty && descriptor.title != descriptor.id && !descriptor.summary.isEmpty)
        }
        #expect(r.binding.descriptors[0].risk == .safe, "media conversion writes new files only")
        #expect(r.binding.descriptors[1].risk == .touchesSystem, "the wallpaper changes the desktop")
        #expect(r.registry.state(for: "mediaTools") == .off && r.registry.state(for: "wallpaper") == .off)
        #expect(r.log.events.isEmpty, "binding starts nothing")
    }

    @Test func theUpstreamCatalogAsksForNoSystemPermissionEither() {
        for feature in [AppFeature.mediaTools, .wallpaper] {
            #expect(feature.permissions.isEmpty, "\(feature)")
            #expect(feature.registryID == feature.rawValue, "a new feature: its switch is its upstream id")
            #expect(PortFeatureIDs.isOwnedByExistingModule(feature.rawValue) == false)
        }
        #expect(PortFeatureBinding.risk(of: .mediaTools) == .safe && PortFeatureBinding.risk(of: .wallpaper) == .touchesSystem)
    }

    @Test func thePagesAreTheMediaAndWallpaperRowsAndCarryTheFeatureCard() {
        let r = rig()
        defer { r.cleanup() }
        let pages = r.binding.pages.map { "\($0.pageID)>\($0.featureID)" }
        #expect(pages == ["media>mediaTools", "wallpaper>wallpaper"])
        #expect(MediaToolsLane.pageIDs == ["mediaTools": "media", "wallpaper": "wallpaper"])
        for id in ["media", "wallpaper"] {
            #expect(SettingsPageCatalog.page(id) != nil, "\(id) is a catalog row")
            #expect(SettingsPageCatalog.page(id)?.featureID == nil, "the binding adds the card itself")
        }
        for page in r.binding.pages { _ = page.body() }  // a body builds without a window or a service
    }

    @Test func aSecondBindingChangesNothing() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        MediaToolsLane.bind(into: binding, runtime: runtime(log))
        MediaToolsLane.bind(into: binding, runtime: runtime(log))
        #expect(binding.descriptors.count == 2 && binding.pages.count == 2)
    }

    // MARK: Start, stop, kill switch

    @Test func switchingOnStartsOnceAndOffStopsAndNeitherNeedsAPermission() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["mediaTools"] = true
        r.registry.switches["mediaTools"] = true
        #expect(r.log.events == ["media.start"], "idempotent")
        #expect(r.registry.state(for: "mediaTools") == .active, "active with every permission missing")
        r.registry.switches["wallpaper"] = true
        #expect(r.log.events == ["media.start", "wallpaper.start"])
        #expect(r.registry.state(for: "wallpaper") == .active)
        r.log.events.removeAll()
        r.registry.switches["mediaTools"] = false
        r.registry.switches["mediaTools"] = false
        #expect(r.log.events == ["media.stop"])
        #expect(r.binding.availability("mediaTools") == false && r.binding.availability("wallpaper") == true)
    }

    @Test func killSwitchSafeModeAndQuarantineStopBothAndTheFeaturesComeBack() {
        let r = rig(media: true, wallpaper: true)
        defer { r.cleanup() }
        #expect(r.log.events == ["media.start", "wallpaper.start"])
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(Set(r.log.events) == ["media.stop", "wallpaper.stop"], "the kill switch stops both: \(r.log.events)")
        #expect(r.binding.availability("mediaTools") == false && r.binding.availability("wallpaper") == false)
        r.log.events.removeAll()
        r.registry.killSwitch = false
        #expect(Set(r.log.events) == ["media.start", "wallpaper.start"])
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.count("media.stop") == 1 && r.log.count("wallpaper.stop") == 1, "safe mode stops them too")
    }

    @Test func theUpstreamAvailabilityFollowsTheRegistryVerdictNotAStoredKey() {
        PortHostFixture.isolated { defaults in
            let r = rig()
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            defaults.set(true, forKey: AppFeature.mediaTools.availabilityKey)  // a stale stored switch
            #expect(AppFeature.mediaTools.isAvailable == false && AppFeature.wallpaper.isAvailable == false)
            r.registry.switches["mediaTools"] = true
            #expect(AppFeature.mediaTools.isAvailable)
            r.registry.killSwitch = true
            #expect(AppFeature.mediaTools.isAvailable == false,
                    "the converter's guards (`isAvailable`) refuse a new run once the registry stopped the feature")
        }
    }

    // MARK: Wiring

    @Test func theLaneIsInTheLaneList() throws {
        let lanes = try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/PortKit/Bridge/PortLanes.swift"),
                               encoding: .utf8)
        #expect(lanes.contains("MediaToolsLane.bind(into:)"))
    }

    @Test func theLiveRuntimeStartsNothingThatApplies() {
        // `wallpaper` start is a preferences re-read, `mediaTools` start a sweep: neither can change a file or the desktop.
        let source = PortSourceScrubTests.files.first { $0.path == "Bridge/MediaTools.swift" }?.lines ?? []
        let text = source.joined(separator: "\n")
        let lifecycle = text.components(separatedBy: "enum WallpaperLifecycle").dropFirst().first?
            .components(separatedBy: "// MARK: - Texts").first ?? ""
        #expect(!lifecycle.isEmpty)
        for banned in [".apply(", "restorePrevious", "setDesktopImageURL", "setImageOnAllSpaces", "Shell.run"] {
            #expect(!lifecycle.contains(banned), "the wallpaper lifecycle must not call \(banned)")
        }
    }
}
