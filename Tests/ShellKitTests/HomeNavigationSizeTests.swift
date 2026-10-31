import CoreGraphics
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

/// The open size is a pure function of the route: the sequence of sizes across a navigation is fixed, and coming
/// back home gives back exactly the home size (nothing sticks to the Explorer's or a page's size).
@MainActor
@Suite struct HomeNavigationSizeTests {
    private func makeContext(_ defaults: UserDefaults, marker: CrashMarker, keyboard: LevelBackend) -> ShellContext {
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, crashMarker: marker)
        registry.switches = Dictionary(uniqueKeysWithValues: ShellDescriptors.all.map {
            ($0.id, ["terminal", "agents", "clipboard"].contains($0.id))
        })
        let tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(EmptyView()) } }
        }
        let home = HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { 0.4 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.7 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: keyboard)
        return ShellContext(tabs: tabs, registry: registry, navigation: ShellNavigation(),
                            quickAccess: QuickAccessModel(defaults: defaults, table: QuickActionTable()), home: home)
    }

    @Test func sizesFollowTheRouteAndHomeComesBackExactly() {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-size-marker-\(UUID().uuidString)"))
        defer { bench.cleanup(); marker.clear() }
        let context = makeContext(bench.defaults, marker: marker, keyboard: .unsupported("x"))
        for mode in IslandSizeMode.allCases {
            context.home.sizeMode = mode
            context.navigation.route = .home
            let home = context.panelSize
            var seen: [CGSize] = []
            for step: IslandRoute in [.explore, .home, .page("agents"), .home, .page("terminal"), .explore, .home] {
                context.navigation.route = step
                let size = context.panelSize
                seen.append(size)
                #expect(size == context.home.panelSize(body: context.bodySize), "\(mode) \(step)")
                switch step {
                case .home: #expect(size == home, "\(mode): home size after a detour")
                case .explore: #expect(context.bodySize.width == context.home.homeBody.width)
                case .page(let id):
                    #expect(context.bodySize == HomeGeometry.pageBody(sectionHeight: ShellLayout.openHeight(forSection: id)))
                }
            }
            // The sequence is the same the second time round: no state is kept between routes.
            var again: [CGSize] = []
            for step: IslandRoute in [.explore, .home, .page("agents"), .home, .page("terminal"), .explore, .home] {
                context.navigation.route = step
                again.append(context.panelSize)
            }
            #expect(seen == again)
        }
    }

    @Test func sliderRowKeepsOnlyTheLevelsTheSystemOffers() {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-size-marker-\(UUID().uuidString)"))
        defer { bench.cleanup(); marker.clear() }

        let without = makeContext(bench.defaults, marker: marker, keyboard: .unsupported("Réglage non disponible"))
        #expect(without.home.availableLevels.map(\.title) == ["Volume", "Luminosité"])
        let help = without.home.unavailableLevelsHelp ?? ""
        #expect(help.contains("Rétroéclairage du clavier"))
        #expect(help.contains("Réglage non disponible"))

        let with = makeContext(bench.defaults, marker: marker,
                               keyboard: LevelBackend(read: { 0.5 }, write: { _ in true }, unavailableReason: "x"))
        #expect(with.home.availableLevels.count == 3)
        #expect(with.home.unavailableLevelsHelp == nil)
    }
}
