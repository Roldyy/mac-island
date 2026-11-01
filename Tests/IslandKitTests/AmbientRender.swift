import AppKit
import Foundation
import IslandUI
import SwiftUI
@testable import IslandKit

/// Renders the closed island through the real pipeline (center, layout model, metrics, strip) in an offscreen
/// window that is never visible: far from every display, alpha 0.
@MainActor enum AmbientRender {
    static var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac-island-closed", isDirectory: true)
    }

    nonisolated static let clock = Date(timeIntervalSince1970: 1_800_000_000)

    /// The hardware band of a 14-inch MacBook Pro (180 pt wide, 32 pt tall); the 16-inch is 200 pt wide.
    nonisolated static let notchWidth: CGFloat = 180
    nonisolated static let notchHeight: CGFloat = 32

    /// Size of the closed island: what `NotchGeometry.closedFrame` gives for the wings the center asks for.
    static func closedSize(center: AmbientCenter, notched: Bool, notchWidth: CGFloat = notchWidth,
                           notchHeight: CGFloat = notchHeight) -> CGSize {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1200)
        let idle: NotchGeometry
        if notched {
            idle = NotchGeometry.idle(
                screenFrame: screen, safeAreaTop: notchHeight,
                auxLeft: CGRect(x: 0, y: screen.maxY - notchHeight, width: (screen.width - notchWidth) / 2, height: notchHeight),
                auxRight: CGRect(x: (screen.width + notchWidth) / 2, y: screen.maxY - notchHeight,
                                 width: (screen.width - notchWidth) / 2, height: notchHeight))
        } else {
            idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        }
        let frame = NotchGeometry.closedFrame(
            from: idle, wingExtent: NotchGeometry.wingExtent(for: center.widthProxy.layout), screenFrame: screen)
        return frame.size
    }

    /// A center in a known state: only the settings and indicators of the scenario.
    static func center(notched: Bool, settings: ClosedIslandSettings = .standard, step: Int = 0,
                       indicators: [AmbientIndicator], activity: ActivityLayout = .empty,
                       claude: ClaudeWorkSample? = nil) -> AmbientCenter {
        let name = "render-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        settings.write(to: defaults)
        defaults.set(true, forKey: ClosedIslandKeys.migrated)
        let activityCenter = ActivityCenter()
        let center = AmbientCenter(
            activity: activityCenter, preferences: ClosedIslandPreferences(defaults: defaults), isNotched: notched,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, now: { clock })
        center.setClaude(claude)
        for item in indicators { center.post(item) }
        if activity != .empty {
            activityCenter.post(IslandActivity(id: "x", source: "x", priority: .alert, leading: activity.leading, trailing: activity.trailing))
        }
        for _ in 0..<step { center.advance() }
        return center
    }

    struct Scene: View {
        let center: AmbientCenter
        let notched: Bool
        let background: Color
        var pulse: Double?
        var notchWidth: CGFloat = AmbientRender.notchWidth
        var notchHeight: CGFloat = AmbientRender.notchHeight

        /// The closed island exactly as the panel sizes it: the notch (or the pill) plus the wings the width
        /// proxy asks for, as tall as the notch.
        var size: CGSize { AmbientRender.closedSize(center: center, notched: notched, notchWidth: notchWidth, notchHeight: notchHeight) }

        var body: some View {
            let idle: CGFloat = notched ? notchWidth : NotchGeometry.pillWidth
            let size = size
            ZStack(alignment: .top) {
                background
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: IslandRevealCurve.closedBottomRadius, style: .continuous)
                        .fill(IslandSurface.notchBlack)
                    AmbientStrip(content: center.content, notchWidth: idle, isNotched: notched, size: size,
                                 clock: AmbientRender.clock, pulsePreview: pulse)
                }
                .frame(width: size.width, height: size.height)
                .padding(.top, 12)
            }
        }
    }

    @discardableResult
    static func png(center: AmbientCenter, notched: Bool, dark: Bool, name: String, pulse: Double? = nil,
                    scale: CGFloat = 2, notchWidth: CGFloat = notchWidth) -> URL? {
        _ = NSApplication.shared
        let size = CGSize(width: 440, height: 58)
        let root = Scene(center: center, notched: notched, background: Color(white: dark ? 0.07 : 0.5), pulse: pulse,
                         notchWidth: notchWidth)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: root)
        let appearance = NSAppearance(named: .darkAqua)
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        // Far off every display and invisible: the window must be ordered in to render, never seen by the user.
        window.setFrameOrigin(CGPoint(x: -40_000, y: -40_000))
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        return url
    }
}
