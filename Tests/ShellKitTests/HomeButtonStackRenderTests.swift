import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import ShellKit

/// The round-button stacks as views: a stack that does not fit scrolls inside the room it has, a stack that fits is
/// exactly as tall as its buttons, and an island with eight buttons per side stays inside its panel.
@MainActor
@Suite(.serialized) struct HomeButtonStackRenderTests {
    private func circles(_ count: Int) -> some View {
        ForEach(0..<count, id: \.self) { _ in Circle().frame(width: 44, height: 44) }
    }

    private func fitting<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test func aColumnThatFitsIsExactlyAsTallAsItsButtonsAndStaysWhereItWas() {
        let size = fitting(HomeButtonStackView(axis: .vertical, count: 3, available: 250, inset: 44) {
            VStack(spacing: HomeButtonStack.spacing) { circles(3) }
        })
        #expect(size.height == 44 + HomeButtonStack.contentLength(count: 3, item: 44, spacing: 12))
    }

    @Test func aColumnThatDoesNotFitTakesTheRoomItHasNotMore() {
        let size = fitting(HomeButtonStackView(axis: .vertical, count: 8, available: 250, inset: 44) {
            VStack(spacing: HomeButtonStack.spacing) { circles(8) }
        })
        #expect(size.height == CGFloat(294), "inset + room: the column never grows the island")
    }

    @Test func aRowThatDoesNotFitTakesTheWidthItHas() {
        let size = fitting(HomeButtonStackView(axis: .horizontal, count: 6, available: 190) {
            HStack(spacing: HomeButtonStack.spacing) { circles(6) }
        })
        #expect(size.width == 190)
        let fits = fitting(HomeButtonStackView(axis: .horizontal, count: 2, available: 190) {
            HStack(spacing: HomeButtonStack.spacing) { circles(2) }
        })
        #expect(fits.width == HomeButtonStack.contentLength(count: 2, item: 44, spacing: 12))
    }

    private func makeContext(_ defaults: UserDefaults, marker: CrashMarker) -> ShellContext {
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, crashMarker: marker)
        let tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(EmptyView()) } }
        }
        let table = QuickActionTable()
        for id in QuickAccessCatalog.defaultIDs { table.register(id) {} }
        let extras = DockCommandRegistry()
        for index in 0..<20 {
            extras.register(DockCommand(id: "port.fill\(index)", title: "Commande \(index)", systemImage: "star",
                                        category: .tools) {})
        }
        let home = HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { 0.45 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.75 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: LevelBackend(read: { 0.9 }, write: { _ in true }, unavailableReason: "x"))
        return ShellContext(tabs: tabs, registry: registry, navigation: ShellNavigation(),
                            quickAccess: QuickAccessModel(defaults: defaults, table: table), home: home,
                            dockExtras: extras)
    }

    @Test func anIslandWithEightButtonsPerSideAndSixBelowStaysInsideItsPanel() throws {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-stack-marker-\(UUID().uuidString)"))
        defer { bench.cleanup(); marker.clear() }
        let context = makeContext(bench.defaults, marker: marker)
        func fill(_ range: Range<Int>, _ side: HomeButtonSide) -> [HomeButton] {
            range.map { HomeButton(actionID: "port.fill\($0)", side: side) }
        }
        context.home.buttons = HomeButtonLayout(buttons: fill(0..<8, .left) + fill(8..<16, .right) + fill(16..<20, .bottom)
            + [HomeButton(actionID: "capture", side: .bottom), HomeButton(actionID: "lockScreen", side: .bottom)])
        #expect(context.home.buttons.buttons(on: .left).count == 8)
        #expect(context.home.buttons.buttons(on: .bottom).count == 6)
        for mode in IslandSizeMode.allCases {
            context.home.sizeMode = mode
            let size = context.panelSize
            // An NSHostingView draws the scroll views (ImageRenderer paints a "no entry" sign in their place).
            let host = NSHostingView(rootView: HomeIslandContent(context: context, notchWidth: 200, notchHeight: 32)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(white: 0.35))
                .environment(\.colorScheme, .dark))
            host.sizingOptions = []
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            // The island's own content must not ask for more than the panel gives it.
            let fit = host.fittingSize
            #expect(fit.height <= size.height + 0.5, "\(mode): \(fit) vs \(size)")
            #expect(fit.width <= size.width + 0.5, "\(mode): \(fit) vs \(size)")
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: HomeSnapshotTests.outputDirectory.appendingPathComponent("buttons-8-\(mode.rawValue).png"))
            #expect(png.count > 4_000)
        }
    }
}
