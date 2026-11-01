import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

/// The ported panels (music, timer, calendar, notifications, accessories, downloads, files, watch, mirror, companion) exist
/// as island tiles only while one of their switches is on; the 12 first panels keep their own switch and dimmed tile.
@MainActor
@Suite struct ShellTabGateTests {
    private func makeContext(extraIDs: [String], enabled: Set<String>, gate: ShellTabGate) -> (ShellContext, () -> Void) {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-gate-marker-\(UUID().uuidString)"))
        // One registry feature per switch the gate names, plus our own descriptors.
        let switches = Set(gate.features.values.flatMap { $0 })
        let extras = switches.sorted().map {
            FeatureDescriptor(id: $0, title: $0, summary: "x", systemImage: "star", category: .tools)
        }
        let descriptors = ShellDescriptors.all + extras
        let registry = FeatureRegistry(descriptors: descriptors, defaults: bench.defaults, crashMarker: marker)
        registry.switches = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, enabled.contains($0.id)) })
        var tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(Color.clear) } }
        }
        tabs += extraIDs.map { IslandTab(id: $0, title: $0, systemImage: "star") { AnyView(Color.clear) } }
        let table = QuickActionTable()
        for id in QuickAccessCatalog.defaultIDs { table.register(id) {} }
        let context = ShellContext(tabs: tabs, registry: registry, navigation: ShellNavigation(),
                                   quickAccess: QuickAccessModel(defaults: bench.defaults, table: table), tabGate: gate)
        return (context, { bench.cleanup(); marker.clear() })
    }

    @Test func aGatedPanelFollowsAnyOneOfItsSwitchesAndAnOtherPanelItsOwn() {
        let gate = ShellTabGate(["music": ["a", "b"], "timer": ["t"]])
        #expect(gate.isEnabled("music") { $0 == "b" })
        #expect(!gate.isEnabled("music") { _ in false })
        #expect(gate.isEnabled("timer") { $0 == "t" } && !gate.isEnabled("timer") { $0 == "a" })
        #expect(gate.isEnabled("terminal") { $0 == "terminal" }, "an ungated panel reads its own id")
        #expect(gate.isOptional("music") && !gate.isOptional("terminal"))
    }

    @Test func thePortedTableNamesTenPanelsAndNoneOfThe12() {
        let ids = Set(ShellTabGate.ported.features.keys)
        #expect(ids == ["music", "timer", "calendar", "notifications", "accessories",
                        "downloads", "filetools", "watch", "mirror", "companion"])
        let own = Set(ShellDescriptors.all.compactMap(\.tabID))
        #expect(ids.isDisjoint(with: own))
        for id in ids { #expect(ShellLayout.openHeights[id] != nil, Comment(rawValue: id)) }
    }

    @Test func anOptionalPanelHasNoTileWhileItsSwitchIsOffAndGetsOneWhenItIsOn() {
        let (off, cleanupOff) = makeContext(extraIDs: ["timer"], enabled: [], gate: .ported)
        defer { cleanupOff() }
        #expect(!off.tileItems(showHidden: true).contains { $0.id == "timer" })
        #expect(!off.isTabEnabled("timer"))
        #expect(!off.isAvailable(HomeAction(id: "timer", title: "t", systemImage: "timer", kind: .page("timer"))))

        let (on, cleanupOn) = makeContext(extraIDs: ["timer"], enabled: ["notchTimer"], gate: .ported)
        defer { cleanupOn() }
        let tile = on.tileItems().first { $0.id == "timer" }
        #expect(tile?.isEnabled == true && tile?.featureID == "timer")
        #expect(on.isTabEnabled("timer"))
    }

    @Test func theMusicPanelOpensWithAnyOfItsThreeSwitches() {
        for switchID in ["notchLyrics", "notchQueue", "notchLiveEqualizer"] {
            let (context, cleanup) = makeContext(extraIDs: ["music"], enabled: [switchID], gate: .ported)
            defer { cleanup() }
            #expect(context.tileItems().contains { $0.id == "music" && $0.isEnabled }, Comment(rawValue: switchID))
        }
        let (none, cleanup) = makeContext(extraIDs: ["music"], enabled: [], gate: .ported)
        defer { cleanup() }
        #expect(!none.tileItems(showHidden: true).contains { $0.id == "music" })
    }

    @Test func theTwelveFirstPanelsKeepTheirDimmedTileWhenOff() {
        let (context, cleanup) = makeContext(extraIDs: ["timer"], enabled: [], gate: .ported)
        defer { cleanup() }
        let tiles = context.tileItems(showHidden: true)
        #expect(tiles.contains { $0.id == "fans" && !$0.isEnabled }, "a switched-off first-wave panel stays, dimmed")
    }
}
