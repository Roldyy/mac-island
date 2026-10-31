import AppKit
import Foundation
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import IslandKit
@testable import ShellKit

/// The real `IslandShellView` in an invisible window (far offscreen, alpha 0), with the panel following
/// `onOpenSize` through `IslandFramePlan` like `IslandController`. Tests drive the navigation like a user,
/// render PNGs under the temp directory (`mac-island-nav`) and check the geometry on the pixels.
@MainActor
final class IslandRig {
    let state = IslandState()
    let window: NSWindow
    let host: NSHostingView<AnyView>
    let context: ShellContext
    /// Every size the shell asked the panel for, in order.
    private(set) var requested: [CGSize] = []
    private var settle: Task<Void, Never>?

    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private final class WeakBox { weak var rig: IslandRig? }

    static let origin = CGPoint(x: -30_000, y: -30_000)

    init(context base: ShellContext) {
        window = OffscreenWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        host = NSHostingView(rootView: AnyView(EmptyView()))
        var wired = base
        let box = WeakBox()
        wired.onOpenSize = { size in box.rig?.panelWants(size) }
        context = wired
        box.rig = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.appearance = NSAppearance(named: .darkAqua)
        host.sizingOptions = []
        window.contentView = host
        host.rootView = AnyView(IslandShellView(context: wired).environmentObject(state))
        setFrame(CGRect(origin: .zero, size: wired.panelSize))
        window.orderFront(nil)
    }

    func close() {
        settle?.cancel()
        window.orderOut(nil)
    }

    private func setFrame(_ rect: CGRect) {
        // Top-centred like the real panel: the top edge and the horizontal centre stay put.
        let frame = CGRect(x: Self.origin.x - rect.width / 2, y: Self.origin.y - rect.height, width: rect.width, height: rect.height)
        window.setFrame(frame, display: true)
        host.frame = CGRect(origin: .zero, size: rect.size)
    }

    var panelFrameSize: CGSize { window.frame.size }

    /// Mirrors `IslandController.move`: grow at once, shrink after the settle delay.
    private func panelWants(_ size: CGSize) {
        requested.append(size)
        settle?.cancel()
        let plan = IslandFramePlan.make(current: CGRect(origin: .zero, size: window.frame.size),
                                        target: CGRect(origin: .zero, size: size), animated: true)
        setFrame(plan.immediate)
        guard let settled = plan.settled else { return }
        settle = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(IslandRevealCurve.settleDelay))
            guard !Task.isCancelled else { return }
            self?.setFrame(settled)
        }
    }

    /// Lets the main actor and the run loop work (animations, observation, settle tasks) for a while.
    func wait(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(10))
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            host.layoutSubtreeIfNeeded()
        }
    }

    /// Waits until the panel window has the size the route asks for (the shrink waits `settleDelay`; a loaded
    /// machine waits longer), so the checks do not depend on the clock.
    func settle(to size: CGSize, timeout: TimeInterval = 5) async {
        let end = Date().addingTimeInterval(timeout)
        while panelFrameSize != size, Date() < end { await wait(0.05) }
        await wait(0.1)
    }

    func snapshot() -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded()
        host.needsDisplay = true
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }
}

extension NSBitmapImageRep {
    /// Brightness (0...1) of the pixel under a point in view coordinates (top-left origin).
    func brightness(x: CGFloat, y: CGFloat, viewWidth: CGFloat) -> Double {
        let scale = CGFloat(pixelsWide) / viewWidth
        let px = Int(x * scale), py = Int(y * scale)
        guard px >= 0, py >= 0, px < pixelsWide, py < pixelsHigh, let c = colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return 0 }
        return Double(max(c.redComponent, c.greenComponent, c.blueComponent)) * Double(c.alphaComponent)
    }
}

extension NSBitmapImageRep {
    func alpha(x: CGFloat, y: CGFloat, viewWidth: CGFloat) -> Double {
        let scale = CGFloat(pixelsWide) / viewWidth
        let px = Int(x * scale), py = Int(y * scale)
        guard px >= 0, py >= 0, px < pixelsWide, py < pixelsHigh, let c = colorAt(x: px, y: py) else { return 0 }
        return Double(c.alphaComponent)
    }
}

@MainActor
@Suite struct HomeNavigationRenderTests {
    static let outputDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-nav")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let threeFeatures: Set<String> = ["terminal", "agents", "clipboard"]

    private func makeContext(_ defaults: UserDefaults, marker: CrashMarker, enabled: Set<String>?,
                             keyboardAvailable: Bool) -> ShellContext {
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, crashMarker: marker)
        if let enabled {
            registry.switches = Dictionary(uniqueKeysWithValues: ShellDescriptors.all.map { ($0.id, enabled.contains($0.id)) })
        }
        let tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(Color.clear) } }
        }
        let table = QuickActionTable()
        for id in QuickAccessCatalog.defaultIDs { table.register(id) {} }
        let home = HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { 0.45 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.75 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: keyboardAvailable
                ? LevelBackend(read: { 0.9 }, write: { _ in true }, unavailableReason: "x")
                : .unsupported("Rétroéclairage du clavier : réglage non disponible"))
        return ShellContext(tabs: tabs, registry: registry, navigation: ShellNavigation(),
                            quickAccess: QuickAccessModel(defaults: defaults, table: table), home: home)
    }

    private func save(_ rep: NSBitmapImageRep, _ name: String) {
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: Self.outputDirectory.appendingPathComponent("\(name).png"))
        }
    }

    /// Lowest y (view points, top origin) of a lit pixel in the body columns, above the bottom button row.
    private func lowestLitRow(_ rep: NSBitmapImageRep, context: ShellContext) -> CGFloat {
        let body = context.bodySize
        let width = context.panelSize.width
        let x0 = HomeGeometry.sideColumn + 24, x1 = HomeGeometry.sideColumn + body.width - 24
        var y = body.height - 1
        while y > 0 {
            var x = x0
            while x < x1 {
                if rep.brightness(x: x, y: y, viewWidth: width) > 0.2 { return y }
                x += 3
            }
            y -= 1
        }
        return 0
    }

    /// The home must be fully drawn: the panel has the size of the route, and the lowest lit pixel of the body is
    /// the label of the last tile row (or lower), not the now-playing card.
    private func expectHomeIntact(_ rig: IslandRig, _ step: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        let context = rig.context
        await rig.settle(to: context.panelSize)
        guard let rep = rig.snapshot() else {
            Issue.record("\(step): no snapshot", sourceLocation: sourceLocation)
            return
        }
        save(rep, step)
        #expect(rig.panelFrameSize == context.panelSize, "\(step): panel \(rig.panelFrameSize) expected \(context.panelSize)",
                sourceLocation: sourceLocation)
        let lastRowTop = context.home.homeBody.height - HomeGeometry.bottomPadding - HomeGeometry.tileRow
        let lowest = lowestLitRow(rep, context: context)
        #expect(lowest > lastRowTop + 20, "\(step): lowest lit row \(lowest), last tile row starts at \(lastRowTop)",
                sourceLocation: sourceLocation)
    }

    private func run(_ label: String, enabled: Set<String>?, mode: IslandSizeMode, customHeight: Double? = nil,
                     keyboardAvailable: Bool = false) async {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-nav-marker-\(UUID().uuidString)"))
        defer { bench.cleanup(); marker.clear() }
        let context = makeContext(bench.defaults, marker: marker, enabled: enabled, keyboardAvailable: keyboardAvailable)
        context.home.sizeMode = mode
        if let customHeight { context.home.customHeight = customHeight }
        let rig = IslandRig(context: context)
        defer { rig.close() }
        let nav = context.navigation
        let tag = "\(label)-\(mode.rawValue)"

        rig.state.isOpen = true
        await rig.wait(0.8)
        await expectHomeIntact(rig, "\(tag)-1-open")

        nav.toggleExplore()
        await rig.wait(0.9)
        await rig.settle(to: context.panelSize)
        if let rep = rig.snapshot() { save(rep, "\(tag)-2-explore") }
        #expect(rig.panelFrameSize == context.panelSize, "\(tag) explore panel \(rig.panelFrameSize) expected \(context.panelSize)")

        let explorePanel = context.panelSize
        nav.toggleExplore()
        // The panel window is still the Explorer's size (it shrinks after `settleDelay`), but the silhouette
        // is the home's already: below the home panel there is nothing drawn.
        await rig.wait(0.15)
        if explorePanel.height > context.panelSize.height + 30, let rep = rig.snapshot() {
            save(rep, "\(tag)-3a-silhouette-before-settle")
            let probe = rep.alpha(x: 200, y: context.panelSize.height + 20, viewWidth: context.panelSize.width)
            #expect(probe < 0.05, "\(tag): silhouette still taller than the home panel (alpha \(probe))")
        }
        await rig.wait(0.8)
        await expectHomeIntact(rig, "\(tag)-3-home-after-explore")

        nav.open(tabID: "agents")
        await rig.wait(0.9)
        await rig.settle(to: context.panelSize)
        if let rep = rig.snapshot() { save(rep, "\(tag)-4-page") }
        #expect(rig.panelFrameSize == context.panelSize, "\(tag) page panel \(rig.panelFrameSize) expected \(context.panelSize)")
        nav.goHome()
        await rig.wait(0.9)
        await expectHomeIntact(rig, "\(tag)-5-home-after-page")

        // Route change in the middle of a shrink / grow.
        nav.toggleExplore()
        await rig.wait(0.1)
        nav.toggleExplore()
        await rig.wait(0.9)
        await expectHomeIntact(rig, "\(tag)-6-fast-explore-roundtrip")

        // Open / close / open within 50 ms.
        rig.state.isOpen = false
        await rig.wait(0.05)
        rig.state.isOpen = true
        await rig.wait(0.9)
        await expectHomeIntact(rig, "\(tag)-7-fast-double-toggle")

        // Close, reopen, and change route twice during the reveal.
        rig.state.isOpen = false
        await rig.wait(0.7)
        rig.state.isOpen = true
        await rig.wait(0.1)
        nav.toggleExplore()
        await rig.wait(0.1)
        nav.toggleExplore()
        await rig.wait(1.0)
        await expectHomeIntact(rig, "\(tag)-8-route-change-during-reveal")
    }

    @Test func threeFeaturesSpacious() async { await run("three", enabled: Self.threeFeatures, mode: .spacious) }
    @Test func threeFeaturesCompact() async { await run("three", enabled: Self.threeFeatures, mode: .compact) }
    @Test func threeFeaturesCustom() async { await run("three", enabled: Self.threeFeatures, mode: .custom, customHeight: 520) }
    @Test func allFeaturesSpacious() async { await run("all", enabled: nil, mode: .spacious, keyboardAvailable: true) }
    @Test func allFeaturesCompact() async { await run("all", enabled: nil, mode: .compact, keyboardAvailable: true) }
    @Test func allFeaturesCustom() async { await run("all", enabled: nil, mode: .custom, customHeight: 520, keyboardAvailable: true) }
}
