import CoreGraphics

enum PanelGeometry {
    static let size = CGSize(width: 640, height: 440)
    static let topInsetFraction = 0.16

    /// Centered horizontally, near the top of the visible area, never off-screen.
    static func frame(in visible: CGRect, size: CGSize = PanelGeometry.size) -> CGRect {
        let w = min(size.width, visible.width), h = min(size.height, visible.height)
        let x = visible.midX - w / 2
        let top = visible.maxY - visible.height * topInsetFraction
        let y = max(visible.minY, top - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
