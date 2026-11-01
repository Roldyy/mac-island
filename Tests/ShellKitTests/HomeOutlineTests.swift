import AppKit
import Foundation
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import IslandKit
@testable import ShellKit

/// The 1 pt outline ("Afficher le contour") must run all around the body: left, right, top corners, the bottom
/// edge and the two bottom corners (radius 26). The real `IslandShellView` is rendered in an invisible window
/// (far offscreen, alpha 0) and the outline is looked for on the pixels. PNGs go to `mac-island-outline` in the
/// temp directory.
@MainActor
@Suite struct HomeOutlineTests {
    static let outputDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-outline")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func makeContext(_ defaults: UserDefaults, marker: CrashMarker) -> ShellContext {
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, crashMarker: marker)
        let tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(Color.clear) } }
        }
        let table = QuickActionTable()
        for id in QuickAccessCatalog.defaultIDs { table.register(id) {} }
        let home = HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { 0.45 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.75 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: .unsupported("x"))
        return ShellContext(tabs: tabs, registry: registry, navigation: ShellNavigation(),
                            quickAccess: QuickAccessModel(defaults: defaults, table: table), home: home)
    }

    /// Brightest pixel (0...1) in a small window around a point, view points, top-left origin.
    private func peak(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat, radius: CGFloat = 1.5, width: CGFloat) -> Double {
        var best = 0.0
        var dy = -radius
        while dy <= radius {
            var dx = -radius
            while dx <= radius {
                best = max(best, rep.brightness(x: x + dx, y: y + dy, viewWidth: width))
                dx += 0.5
            }
            dy += 0.5
        }
        return best
    }

    /// Worst (lowest) peak brightness along a polyline of points; returns it with the first point that fails.
    private func weakest(_ rep: NSBitmapImageRep, _ points: [CGPoint], width: CGFloat) -> (value: Double, at: CGPoint) {
        var worst = (value: 2.0, at: CGPoint.zero)
        for p in points {
            let v = peak(rep, x: p.x, y: p.y, width: width)
            if v < worst.value { worst = (v, p) }
        }
        return worst
    }

    /// How the island got to its open home before the outline is checked.
    private enum Path { case direct, toggledLive, reopened, afterExplorer }

    private func run(_ label: String, mode: IslandSizeMode, translucent: Bool, bottomButtons: Bool, sideButtons: Bool = true,
                     customHeight: Double? = nil, path: Path = .direct) async {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-outline-marker-\(UUID().uuidString)"))
        defer { bench.cleanup(); marker.clear() }
        let context = makeContext(bench.defaults, marker: marker)
        context.home.sizeMode = mode
        if let customHeight { context.home.customHeight = customHeight }
        context.home.translucentBackground = translucent
        context.home.showsOutline = path != .toggledLive
        var layout = HomeButtonLayout.initial
        if !bottomButtons { layout.buttons.removeAll { $0.side == .bottom } }
        if !sideButtons { layout.buttons.removeAll { $0.side != .bottom } }
        context.home.buttons = layout
        let rig = IslandRig(context: context)
        defer { rig.close() }
        rig.state.isOpen = true
        await rig.wait(0.8)
        switch path {
        case .direct: break
        case .toggledLive:
            context.home.showsOutline = true  // the right-click menu toggle, island already open
            await rig.wait(0.4)
        case .reopened:
            rig.state.isOpen = false
            await rig.wait(0.7)
            rig.state.isOpen = true
            await rig.wait(0.9)
        case .afterExplorer:
            context.navigation.toggleExplore()
            await rig.wait(0.9)
            context.navigation.toggleExplore()
            await rig.wait(1.0)
        }
        await rig.settle(to: context.panelSize)
        guard let rep = rig.snapshot() else {
            Issue.record("\(label): no snapshot")
            return
        }
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: Self.outputDirectory.appendingPathComponent("\(label).png"))
        }
        let panel = context.panelSize, body = context.bodySize
        #expect(rig.panelFrameSize == panel, "\(label): panel \(rig.panelFrameSize) expected \(panel)")
        let sides = sideButtons
        let x0 = sides ? HomeGeometry.sideColumn : 0
        let x1 = x0 + body.width
        let top: CGFloat = 0.5, bottom = body.height - 0.5
        let r: CGFloat = 26
        // Edges: the stroke sits half a point inside the body rect.
        let edges: [(String, [CGPoint])] = [
            ("left", stride(from: 20, to: Double(body.height - r - 2), by: 3).map { CGPoint(x: x0 + 0.5, y: $0) }),
            ("right", stride(from: 20, to: Double(body.height - r - 2), by: 3).map { CGPoint(x: x1 - 0.5, y: $0) }),
            ("bottom", stride(from: Double(x0 + r + 2), to: Double(x1 - r - 2), by: 3).map { CGPoint(x: $0, y: bottom) }),
        ]
        let threshold = translucent ? 0.1 : 0.15
        for (name, points) in edges {
            let w = weakest(rep, points, width: panel.width)
            #expect(w.value > threshold, "\(label): \(name) edge weakest \(w.value) at \(w.at) (body \(body), panel \(panel))")
        }
        // Bottom corners: walk the arc (continuous corners stay within ~1.5 pt of a circle of radius 26).
        for (name, cx) in [("bottom-left", x0 + r), ("bottom-right", x1 - r)] {
            let cy = body.height - r
            let arc = stride(from: 10.0, to: 80.0, by: 5).map { deg -> CGPoint in
                let a = deg * .pi / 180
                let sx: CGFloat = name == "bottom-left" ? -1 : 1
                return CGPoint(x: cx + sx * (r - 0.5) * CGFloat(sin(a)), y: cy + (r - 0.5) * CGFloat(cos(a)))
            }
            let w = weakest(rep, arc, width: panel.width)
            #expect(w.value > threshold, "\(label): \(name) corner weakest \(w.value) at \(w.at)")
        }
        // Top: the straight run between the two 12 pt corners, below the notch band is not needed (sides of the strip).
        let w = weakest(rep, stride(from: Double(x0 + 20), to: Double(x0 + 60), by: 3).map { CGPoint(x: $0, y: top) }, width: panel.width)
        #expect(w.value > threshold, "\(label): top edge weakest \(w.value) at \(w.at)")
    }

    @Test func spaciousSolid() async { await run("spacious-solid", mode: .spacious, translucent: false, bottomButtons: true) }
    @Test func spaciousTranslucent() async { await run("spacious-glass", mode: .spacious, translucent: true, bottomButtons: true) }
    @Test func compactSolid() async { await run("compact-solid", mode: .compact, translucent: false, bottomButtons: true) }
    @Test func compactTranslucent() async { await run("compact-glass", mode: .compact, translucent: true, bottomButtons: true) }
    @Test func customSolid() async { await run("custom-solid", mode: .custom, translucent: false, bottomButtons: true, customHeight: 520) }
    @Test func customTranslucent() async { await run("custom-glass", mode: .custom, translucent: true, bottomButtons: true, customHeight: 520) }
    @Test func spaciousToggledWhileOpen() async {
        await run("spacious-toggled", mode: .spacious, translucent: false, bottomButtons: true, path: .toggledLive)
    }
    @Test func spaciousReopened() async {
        await run("spacious-reopened", mode: .spacious, translucent: false, bottomButtons: true, path: .reopened)
    }
    @Test func spaciousAfterExplorer() async {
        await run("spacious-explorer", mode: .spacious, translucent: false, bottomButtons: true, path: .afterExplorer)
    }
    @Test func spaciousNoBottomButtons() async { await run("spacious-nobottom", mode: .spacious, translucent: false, bottomButtons: false) }
    @Test func spaciousNoButtonsAtAll() async {
        await run("spacious-nobuttons", mode: .spacious, translucent: false, bottomButtons: false, sideButtons: false)
    }
}
