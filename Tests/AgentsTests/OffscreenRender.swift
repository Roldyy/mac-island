import AppKit
import SwiftUI
@testable import AgentsFeature

/// Renders a SwiftUI view through a real `NSHostingView` in an offscreen window, so ScrollView, material,
/// `.onAppear` and animations behave as in the app (`ImageRenderer` draws none of those).
@MainActor enum OffscreenRender {
    static var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac-island-agents", isDirectory: true)
    }

    /// `height` nil = the view's own fitting height. `settle` lets the entry animations finish before the capture.
    @discardableResult
    static func png<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, name: String,
                             settle: TimeInterval = 1.4, scale: CGFloat = 2) -> URL? {
        _ = NSApplication.shared
        let dark = NSAppearance(named: .darkAqua)
        let root = view
            .frame(width: width, height: height)
            .background(Color(white: 0.04))
            .environment(\.colorScheme, .dark)
            .environment(\.agentsSettled, true)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = dark
        let size = CGSize(width: width, height: height ?? max(hosting.fittingSize.height, 10))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = dark
        window.contentView = hosting
        // Far off every display and invisible: the window must be ordered in to render, never seen by the user.
        window.setFrameOrigin(CGPoint(x: -40_000, y: -40_000))
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
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
