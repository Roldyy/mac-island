import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import ShellKit

/// The home grid in a real hosting view inside an invisible window (far offscreen, alpha 0), rendered to PNGs
/// under the temp directory (`mac-island-home-tiles`): look at them. Three sizes, three cases each: every feature
/// on, only three on (terminal, agents, clipboard) and 25 tiles with the grid at the top and scrolled.
@MainActor
@Suite struct HomeTileRenderTests {
    static let outputDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-home-tiles")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private func makeContext(_ defaults: UserDefaults, marker: CrashMarker, enabled: Set<String>?, extra: Int = 0) -> ShellContext {
        let extras = (0..<extra).map {
            FeatureDescriptor(id: "extra\($0)", title: "Outil \($0 + 1)", summary: "x", systemImage: "star", category: .tools,
                              tabID: "extra\($0)")
        }
        let descriptors = ShellDescriptors.all + extras
        let registry = FeatureRegistry(descriptors: descriptors, defaults: defaults, crashMarker: marker)
        if let enabled {
            registry.switches = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, enabled.contains($0.id)) })
        }
        let tabs = descriptors.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(Color.clear) } }
        }
        let table = QuickActionTable()
        for id in QuickAccessCatalog.defaultIDs { table.register(id) {} }
        let home = HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { 0.45 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.75 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: LevelBackend(read: { 0.9 }, write: { _ in true }, unavailableReason: "x"))
        return ShellContext(tabs: tabs, registry: registry, navigation: ShellNavigation(),
                            quickAccess: QuickAccessModel(defaults: defaults, table: table), home: home)
    }

    private func settle(_ host: NSView, seconds: TimeInterval = 0.4) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(10))
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            host.layoutSubtreeIfNeeded()
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews(in:))
    }

    /// Draws the island (home or Explorer) once per requested scroll offset and writes `<name>.png`.
    @discardableResult
    private func render(_ name: String, _ context: ShellContext, scrolledBy offsets: [CGFloat] = [0]) async throws -> [Data] {
        let size = context.panelSize
        let window = OffscreenWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: AnyView(
            HomeIslandContent(context: context, notchWidth: 200, notchHeight: 32)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(white: 0.35))
                .environment(\.colorScheme, .dark)))
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(CGRect(x: -30_000 - size.width / 2, y: -30_000 - size.height, width: size.width, height: size.height),
                        display: true)
        host.frame = CGRect(origin: .zero, size: size)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        await settle(host)

        var images: [Data] = []
        for (index, offset) in offsets.enumerated() {
            if offset > 0, let scroll = scrollViews(in: host).first {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scroll.reflectScrolledClipView(scroll.contentView)
                await settle(host, seconds: 1.0)
            }
            host.needsDisplay = true
            host.displayIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            let file = offsets.count == 1 ? name : "\(name)-\(index == 0 ? "top" : "scrolled")"
            try png.write(to: Self.outputDirectory.appendingPathComponent("\(file).png"))
            #expect(png.count > 4_000, "\(file) looks blank")
            images.append(png)
        }
        return images
    }

    private func bench() -> (defaults: UserDefaults, marker: CrashMarker, cleanup: () -> Void) {
        let b = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-tiles-marker-\(UUID().uuidString)"))
        return (b.defaults, marker, { b.cleanup(); marker.clear() })
    }

    @Test func allFeaturesEnabledAtTheThreeSizes() async throws {
        let b = bench()
        defer { b.cleanup() }
        let context = makeContext(b.defaults, marker: b.marker, enabled: nil)
        #expect(context.tileItems().count == 18)
        for mode in IslandSizeMode.allCases {
            context.home.sizeMode = mode
            try await render("a-all-\(mode.rawValue)", context)
        }
        context.navigation.route = .explore
        try await render("a-all-explore", context)
    }

    @Test func onlyThreeFeaturesEnabledShowsTheOthersDimmedAtTheEnd() async throws {
        let b = bench()
        defer { b.cleanup() }
        let context = makeContext(b.defaults, marker: b.marker, enabled: ["terminal", "agents", "clipboard"])
        let tiles = context.tileItems()
        #expect(tiles.count == 18 && tiles.filter(\.isEnabled).count == 7)
        for mode in IslandSizeMode.allCases {
            context.home.sizeMode = mode
            try await render("b-three-\(mode.rawValue)", context)
        }
    }

    @Test func twentyFiveTilesScrollUnderThePinnedHeader() async throws {
        let b = bench()
        defer { b.cleanup() }
        let context = makeContext(b.defaults, marker: b.marker, enabled: nil, extra: 9)
        #expect(context.tileItems().count == 27)
        context.home.customHeight = 640
        for mode in IslandSizeMode.allCases {
            context.home.sizeMode = mode
            let rows = context.home.tileRows(tileCount: 26)
            let columns = context.home.tileColumns
            let scrollable = HomeTileCatalog.rows(context.tileItems(), columns: columns).count > rows
            // Scrolled to the end of the content (a clip view does not stop an offset beyond it).
            let totalRows = HomeTileCatalog.rows(context.tileItems(), columns: columns).count
            let images = try await render("c-25-\(mode.rawValue)", context,
                                          scrolledBy: scrollable ? [0, CGFloat(totalRows - rows) * HomeGeometry.tileRow] : [0])
            if scrollable { #expect(images[0] != images[1], "\(mode): scrolling changed nothing") }
        }
    }

    @Test func hidingATileRemovesItFromTheHomeAndTheExplorerKeepsIt() async throws {
        let b = bench()
        defer { b.cleanup() }
        let context = makeContext(b.defaults, marker: b.marker, enabled: nil)
        context.home.hideTile("capture")
        context.home.hideTile("dock")
        #expect(context.tileItems().count == 16)
        try await render("d-hidden-home", context)
        context.navigation.route = .explore
        #expect(context.tileItems(showHidden: true).count == 18)
        try await render("d-hidden-explore", context)
    }
}
