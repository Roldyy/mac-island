import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import IslandExtrasFeature
@testable import ShellKit

@MainActor
@Suite struct IslandExtrasRegistrationTests {
    let bench = TestDefaults.make()
    let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))

    func registry() -> FeatureRegistry {
        FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker, withdraw: { _ in })
    }

    static let ids = ["notesTab", "colorsTab", "batteryTab", "networkNotice"]

    @Test func theTabsHaveStableIdsAndFrenchTitles() {
        let tabs = IslandExtrasFeature.tabs()
        #expect(tabs.map(\.id) == ["notesTab", "colorsTab", "batteryTab"])
        #expect(tabs.map(\.title) == ["Notes", "Couleurs", "Batterie"])
    }

    @Test func everyDescriptorIsRegisteredOnceOffByDefaultWithNoPermission() {
        defer { bench.cleanup(); marker.clear() }
        for id in Self.ids {
            let matches = ShellDescriptors.all.filter { $0.id == id }
            #expect(matches.count == 1, Comment(rawValue: id))
            #expect(!matches[0].enabledByDefault && matches[0].permissions.isEmpty, Comment(rawValue: id))
            #expect(registry().state(for: id) == .off, Comment(rawValue: id))
        }
        let tabIDs = Set(IslandExtrasFeature.tabs().map(\.id))
        #expect(Set(ShellDescriptors.all.filter { Self.ids.contains($0.id) }.compactMap(\.tabID)) == tabIDs)
        #expect(ShellDescriptors.all.first { $0.id == "networkNotice" }?.tabID == nil, "a notice has no tab")
    }

    @Test func theRegistryStartsAndStopsTheNetworkNoticeAndTheKillSwitchStopsIt() {
        defer { bench.cleanup(); marker.clear() }
        let r = registry()
        var events: [String] = []
        r.launch(starters: ["networkNotice": { events.append("start") }], stoppers: ["networkNotice": { events.append("stop") }])
        #expect(events.isEmpty, "off by default: launching starts nothing")
        r.switches["networkNotice"] = true
        #expect(events == ["start"])
        r.killSwitch = true
        #expect(events == ["start", "stop"])
    }

    @Test func startAndStopAreIdempotentAndIgnoreUnknownIds() {
        IslandExtrasFeature.stop("networkNotice")
        IslandExtrasFeature.start("networkNotice")
        IslandExtrasFeature.start("networkNotice")
        #expect(IslandExtrasFeature.isRunning("networkNotice"))
        IslandExtrasFeature.stop("networkNotice")
        IslandExtrasFeature.stop("networkNotice")
        #expect(!IslandExtrasFeature.isRunning("networkNotice"))
        IslandExtrasFeature.start("nothing")
        #expect(!IslandExtrasFeature.isRunning("nothing"))
    }
}
