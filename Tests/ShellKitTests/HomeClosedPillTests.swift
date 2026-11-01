import AppKit
import Foundation
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import IslandKit
@testable import ShellKit

/// The real `IslandShellView` and the real `ClosedStrip`, in an invisible window (far offscreen, alpha 0) that
/// follows the panel the way `IslandController` does: closed frame at rest, the route's size while open,
/// grow at once and shrink after `settleDelay`.
@MainActor
final class ClosedPillRig {
    let state = IslandState()
    let window: NSWindow
    let host: NSHostingView<AnyView>
    let center: AmbientCenter
    let activity = ActivityCenter()
    let notched: Bool
    let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private(set) var context: ShellContext!
    private var openSize = CGSize.zero
    private(set) var isOpen = false
    private var settleTask: Task<Void, Never>?
    private let bench = TestDefaults.make()
    private let marker: CrashMarker

    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private final class WeakBox { weak var rig: ClosedPillRig? }

    static let origin = CGPoint(x: -30_000, y: -30_000)
    static let outputDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-pill")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init(notched: Bool, reduceMotion: Bool = false) {
        self.notched = notched
        marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-pill-marker-\(UUID().uuidString)"))
        let defaults = bench.defaults
        center = AmbientCenter(
            activity: activity, preferences: ClosedIslandPreferences(defaults: defaults), isNotched: notched,
            rotationInterval: .seconds(3600))
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
        let center = self.center
        let box = WeakBox()
        let base = ShellContext(
            tabs: tabs, registry: registry, navigation: ShellNavigation(),
            quickAccess: QuickAccessModel(defaults: defaults, table: table), home: home,
            closedStrip: { AnyView(ClosedStrip(ambient: center)) },
            onOpenSize: { size in box.rig?.panelWants(size) })
        context = base
        window = OffscreenWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        host = NSHostingView(rootView: AnyView(EmptyView()))
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        host.sizingOptions = []
        window.contentView = host
        host.rootView = AnyView(
            IslandShellView(context: base, reduceMotionOverride: reduceMotion).environmentObject(state))
        box.rig = self
        openSize = base.panelSize
        refreshClosed(animated: false)
        window.orderFront(nil)
    }

    func close() {
        settleTask?.cancel()
        window.orderOut(nil)
        bench.cleanup()
        marker.clear()
    }

    // MARK: - Panel, as IslandController does it

    var idle: NotchGeometry {
        NotchGeometry.idle(
            screenFrame: screen, safeAreaTop: notched ? 34 : 0,
            auxLeft: notched ? CGRect(x: 0, y: 1406, width: 1627.5, height: 34) : nil,
            auxRight: notched ? CGRect(x: 1812.5, y: 1406, width: 1627.5, height: 34) : nil)
    }

    var closedFrame: CGRect {
        NotchGeometry.closedFrame(
            from: idle, wingExtent: NotchGeometry.wingExtent(for: center.widthProxy.layout), screenFrame: screen)
    }

    /// What `IslandController.updateNotchMetrics` / `layoutChanged` do after a content or screen change.
    func refreshClosed(animated: Bool = true) {
        state.notchWidth = idle.frame.width
        state.notchHeight = idle.frame.height
        state.closedWidth = closedFrame.width
        state.closedHeight = closedFrame.height
        if !isOpen { move(to: closedFrame.size, animated: animated) }
    }

    private func panelWants(_ size: CGSize) {
        openSize = size
        if isOpen { move(to: size, animated: true) }
    }

    func setOpen(_ open: Bool) {
        if open {
            isOpen = true
            move(to: openSize, animated: true)
            state.isOpen = true
        } else {
            isOpen = false
            state.isOpen = false
            move(to: closedFrame.size, animated: true)
        }
    }

    private func move(to size: CGSize, animated: Bool) {
        settleTask?.cancel()
        let plan = IslandFramePlan.make(current: CGRect(origin: .zero, size: window.frame.size),
                                        target: CGRect(origin: .zero, size: size), animated: animated)
        setFrame(plan.immediate.size)
        guard let settled = plan.settled else { return }
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(IslandRevealCurve.settleDelay))
            guard !Task.isCancelled else { return }
            self?.setFrame(settled.size)
        }
    }

    private func setFrame(_ size: CGSize) {
        let frame = CGRect(x: Self.origin.x - size.width / 2, y: Self.origin.y - size.height, width: size.width, height: size.height)
        window.setFrame(frame, display: true)
        host.frame = CGRect(origin: .zero, size: size)
    }

    // MARK: - Driving and reading

    func wait(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(10))
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            host.layoutSubtreeIfNeeded()
        }
    }

    /// Lets the content settle, then makes the panel the closed size (the shrink waits `settleDelay`).
    func settleClosed() async {
        let end = Date().addingTimeInterval(5)
        while window.frame.size != closedFrame.size, Date() < end { await wait(0.05) }
        await wait(0.3)
    }

    func snapshot() -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded()
        host.needsDisplay = true
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    func indicator(_ id: String, symbol: String, text: String? = nil, wing: AmbientWing = .trailing) -> AmbientIndicator {
        AmbientIndicator(id: id, channel: AmbientChannel.keepAwake, symbol: symbol, text: text, status: .info, wing: wing,
                         label: id)
    }
}

extension NSBitmapImageRep {
    /// Opacity (0...1) of the pixel under a point in view coordinates (top-left origin); 0 outside the image.
    func coverage(x: CGFloat, y: CGFloat, viewWidth: CGFloat) -> Double {
        let scale = CGFloat(pixelsWide) / viewWidth
        let px = Int(x * scale), py = Int(y * scale)
        guard px >= 0, py >= 0, px < pixelsWide, py < pixelsHigh, let c = colorAt(x: px, y: py) else { return 0 }
        return Double(c.alphaComponent)
    }
}

@MainActor
@Suite struct HomeClosedPillTests {
    /// The smallest closed island on a screen with no notch: 200 pt pill plus a 16 pt wing each side.
    static let minimumWidth: CGFloat = 190
    static let minimumHeight: CGFloat = 28

    /// A black, opaque pill of at least the minimum size sits at the top centre, whatever it shows.
    private func expectPill(_ rig: ClosedPillRig, _ step: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        await rig.settleClosed()
        guard let rep = rig.snapshot() else {
            Issue.record("\(step): no snapshot", sourceLocation: sourceLocation)
            return
        }
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: ClosedPillRig.outputDirectory.appendingPathComponent("\(step).png"))
        }
        let width = rig.host.bounds.width
        let closed = rig.closedFrame.size
        #expect(rig.window.frame.size == closed, "\(step): panel \(rig.window.frame.size) expected \(closed)", sourceLocation: sourceLocation)
        let midX = width / 2

        // Horizontal run of drawn pixels through the pill's middle row, outward from the centre.
        var left = midX, right = midX
        let row = closed.height / 2
        while left > 0, rep.coverage(x: left - 1, y: row, viewWidth: width) > 0.5 { left -= 1 }
        while right < width, rep.coverage(x: right + 1, y: row, viewWidth: width) > 0.5 { right += 1 }
        #expect(right - left >= Self.minimumWidth, "\(step): pill is \(right - left) pt wide", sourceLocation: sourceLocation)

        // Vertical run through the centre column, from the top edge.
        var bottom: CGFloat = 0
        while bottom < rep.size.height, rep.coverage(x: midX, y: bottom + 1, viewWidth: width) > 0.5 { bottom += 1 }
        #expect(bottom >= Self.minimumHeight, "\(step): pill is \(bottom) pt tall", sourceLocation: sourceLocation)

        // Black on the quiet parts: the top rim just inside the corners, and the strip next to the notch gap.
        let rim = rep.coverage(x: midX, y: 2, viewWidth: width)
        #expect(rim > 0.9, "\(step): top rim alpha \(rim)", sourceLocation: sourceLocation)
        let inner = rep.brightness(x: midX - closed.width / 2 + 20, y: 3, viewWidth: width)
        #expect(inner < 0.3, "\(step): top left of the pill is not black (\(inner))", sourceLocation: sourceLocation)
    }

    private func scenarios(notched: Bool, reduceMotion: Bool) async {
        let tag = "\(notched ? "notch" : "flat")\(reduceMotion ? "-rm" : "")"
        let rig = ClosedPillRig(notched: notched, reduceMotion: reduceMotion)
        defer { rig.close() }

        await rig.wait(0.3)
        await expectPill(rig, "\(tag)-1-nothing-to-show")

        rig.center.post(rig.indicator("battery", symbol: "battery.50", text: "50 %"))
        rig.refreshClosed()
        await expectPill(rig, "\(tag)-2-one-indicator")

        rig.center.post(rig.indicator("keepawake", symbol: "cup.and.saucer.fill", wing: .leading))
        rig.refreshClosed()
        await expectPill(rig, "\(tag)-3-two-indicators")

        rig.center.withdraw(id: "battery")
        rig.center.withdraw(id: "keepawake")
        rig.refreshClosed()
        await expectPill(rig, "\(tag)-4-indicators-gone")

        rig.setOpen(true)
        await rig.wait(0.8)
        rig.setOpen(false)
        await expectPill(rig, "\(tag)-5-open-then-close")

        // Hover in and out within 50 ms, then a few more times.
        for _ in 0..<3 {
            rig.setOpen(true)
            await rig.wait(0.05)
            rig.setOpen(false)
            await rig.wait(0.05)
        }
        await expectPill(rig, "\(tag)-6-quick-hover")

        // Close while the strip is being removed after a full open, with an indicator arriving meanwhile.
        rig.setOpen(true)
        await rig.wait(0.5)
        rig.center.post(rig.indicator("battery", symbol: "battery.50", text: "50 %"))
        rig.setOpen(false)
        rig.refreshClosed()
        await expectPill(rig, "\(tag)-7-indicator-during-close")

        // Rotation: three rotating indicators, one step.
        rig.center.post(rig.indicator("keepawake", symbol: "cup.and.saucer.fill"))
        rig.center.post(rig.indicator("alt", symbol: "bolt.fill", text: "ok"))
        rig.refreshClosed()
        rig.center.advance()
        rig.refreshClosed()
        await expectPill(rig, "\(tag)-8-rotation-step")

        rig.setOpen(true)
        await rig.wait(0.8)
        rig.center.withdraw(id: "battery")
        rig.center.withdraw(id: "keepawake")
        rig.center.withdraw(id: "alt")
        rig.refreshClosed()
        rig.setOpen(false)
        await expectPill(rig, "\(tag)-9-indicators-gone-while-open")
    }

    @Test func noNotch() async { await scenarios(notched: false, reduceMotion: false) }
    @Test func noNotchReduceMotion() async { await scenarios(notched: false, reduceMotion: true) }
    @Test func notched() async { await scenarios(notched: true, reduceMotion: false) }
    @Test func notchedReduceMotion() async { await scenarios(notched: true, reduceMotion: true) }
}
