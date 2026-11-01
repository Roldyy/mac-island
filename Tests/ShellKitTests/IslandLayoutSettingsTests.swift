import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

/// The island page's editors (lane G). Temp defaults only; the render goes to a PNG a person can look at.
@MainActor
@Suite(.serialized) struct IslandLayoutSettingsTests {
    private func makeHome(_ defaults: UserDefaults) -> HomeModel {
        HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { 0.4 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.7 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: LevelBackend(read: { 0.9 }, write: { _ in true }, unavailableReason: "x"))
    }

    @Test func hiddenSummaryAgreesInNumber() {
        #expect(IslandLayoutSettings.hiddenSummary(count: 0) == "Aucun raccourci masqué")
        #expect(IslandLayoutSettings.hiddenSummary(count: 1) == "1 raccourci masqué")
        #expect(IslandLayoutSettings.hiddenSummary(count: 3) == "3 raccourcis masqués")
    }

    /// With a body registered, the noted rows (Taille, Fond translucide...) stop showing as greyed "Bientôt" rows;
    /// the live indicator controls stay. Without a body the page is exactly as before.
    @Test func aBodyDropsThePlannedRowsAndKeepsTheLiveOnes() throws {
        let page = try #require(SettingsPageCatalog.page("island"))
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        let before = SettingsPageModel.blocks(for: page).flatMap(\.rows)
        #expect(before.contains { !$0.isLive }, "the reference rows are planned until a body owns the page")
        #expect(before.contains { $0.isLive })

        SettingsPageBodies.register(pageID: "island") { AnyView(Text("corps")) }
        let after = SettingsPageModel.blocks(for: page).flatMap(\.rows)
        #expect(!after.isEmpty && after.allSatisfy { $0.isLive })
        #expect(after.count == before.filter(\.isLive).count)
    }

    @Test func editingTheModelWritesTheKeysOfTheIsland() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let home = makeHome(bench.defaults)
        home.sizeMode = .custom
        home.translucentBackground = true
        home.notchFitWidth = 99  // clamped to the range
        #expect(bench.defaults.string(forKey: "notchSize") == "custom")
        #expect(bench.defaults.bool(forKey: "notchTranslucentBackground"))
        #expect(bench.defaults.double(forKey: "notchCameraFitWidth") == HomeModel.fitWidthRange.upperBound)
        var layout = home.buttons
        #expect(layout.buttons.count == HomeButtonLayout.initial.buttons.count)
        let first = layout.buttons[0]
        let moved = layout.move(id: first.id, to: .bottom)
        #expect(moved)
        home.buttons = layout
        #expect(HomeButtonLayout.decode(bench.defaults.data(forKey: "notchQuickAccessLayout")).buttons.contains { $0.id == first.id && $0.side == .bottom })
    }

    @Test func rendersTheIslandPage() throws {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let home = makeHome(bench.defaults)
        SettingsPageBodies.removeAll()
        SettingsPageBodies.register(pageID: "island") { AnyView(IslandLayoutSettings(home: home, openIsland: {})) }
        defer { SettingsPageBodies.removeAll() }
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-island-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker)
        let env = SettingsEnvironment(
            registry: registry, defaults: bench.defaults, sheetTabs: [:], openPermission: { _ in }, relaunch: nil,
            login: LoginItemModel(defaults: bench.defaults),
            backup: SettingsBackup(defaults: bench.defaults, domain: "render", directory: URL(fileURLWithPath: NSTemporaryDirectory())))
        let dir = ProcessInfo.processInfo.environment["MIS_RENDER_DIR"] ?? NSTemporaryDirectory()
        let view = SettingsPageView(pageID: "island", env: env)
            .frame(width: 760, height: 1500)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 1500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-island-layout.png"))
        #expect(png.count > 5_000)
    }
}

/// The status item's pure choices: which symbol, which click opens the menu.
@MainActor @Suite struct MenuBarItemControllerTests {
    @Test func theStoredSymbolIsUsedOnlyWhenThisMacHasIt() {
        #expect(MenuBarItemController.symbolName(stored: nil, exists: { _ in true }) == MenuBarItemController.defaultSymbol)
        #expect(MenuBarItemController.symbolName(stored: "  ", exists: { _ in true }) == MenuBarItemController.defaultSymbol)
        #expect(MenuBarItemController.symbolName(stored: "bolt.fill", exists: { $0 == "bolt.fill" }) == "bolt.fill")
        #expect(MenuBarItemController.symbolName(stored: "no.such.symbol", exists: { _ in false }) == MenuBarItemController.defaultSymbol)
    }

    @Test func rightClickAndControlClickOpenTheMenu() {
        #expect(MenuBarItemController.opensMenu(type: .rightMouseUp, modifiers: []))
        #expect(MenuBarItemController.opensMenu(type: .leftMouseUp, modifiers: [.control]))
        #expect(!MenuBarItemController.opensMenu(type: .leftMouseUp, modifiers: []))
        #expect(!MenuBarItemController.opensMenu(type: nil, modifiers: [.shift]))
    }

    @Test func theIconKeyIsTheOneTheIconPickerWrites() {
        #expect(MenuBarItemController.symbolKey == "menuBarIconSymbol")
        #expect(MenuBarItemController.titles(canRelaunch: true) == ["Ouvrir Réglages…", "Relancer Mac Island", "Quitter Mac Island"])
    }
}
