import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import ShellKit

/// Renders the open island home at the three sizes (and the Explorer) to PNGs under the temp directory,
/// and checks each render is not blank. Look at the files by hand against the reference screenshot.
@MainActor
@Suite struct HomeSnapshotTests {
    static let outputDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-home")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func makeContext(_ defaults: UserDefaults, marker: CrashMarker) -> ShellContext {
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, crashMarker: marker)
        let tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(EmptyView()) } }
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

    private func render(_ name: String, _ context: ShellContext) throws {
        let size = context.panelSize
        let view = HomeIslandContent(context: context, notchWidth: 200, notchHeight: 32)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(white: 0.35))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: Self.outputDirectory.appendingPathComponent("\(name).png"))
        #expect(image.width == Int(size.width * 2))
        #expect(png.count > 4_000)  // a collapsed view encodes to almost nothing
    }

    @Test func homeAtTheThreeSizesAndExplorer() throws {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-home-marker-\(UUID().uuidString)"))
        defer { bench.cleanup(); marker.clear() }
        let context = makeContext(bench.defaults, marker: marker)
        for mode in IslandSizeMode.allCases {
            context.home.sizeMode = mode
            try render("home-\(mode.rawValue)", context)
        }
        context.home.sizeMode = .spacious
        context.home.track = HomeTrack(title: "Reason (Bonobo Rework)", artist: "Bonobo", isPlaying: true, progress: 0.4)
        try render("home-playing", context)
        context.navigation.route = .explore
        try render("explore", context)
    }
}
