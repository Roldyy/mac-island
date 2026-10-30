import CoreGraphics

enum DockEdge: Equatable { case bottom, left, right }

/// Cocoa coordinates (origin bottom left) throughout.
enum DockGeometry {
    /// Where the Dock sits, read from the space it reserves. `nil` when it auto-hides (nothing reserved).
    static func edge(screenFrame f: CGRect, visibleFrame v: CGRect) -> DockEdge? {
        if v.minY - f.minY > 1 { return .bottom }
        if v.minX - f.minX > 1 { return .left }
        if f.maxX - v.maxX > 1 { return .right }
        return nil
    }

    /// The strip of the screen the Dock occupies: the pointer is only looked up through Accessibility inside it.
    static func band(screenFrame f: CGRect, visibleFrame v: CGRect) -> CGRect? {
        switch edge(screenFrame: f, visibleFrame: v) {
        case .bottom: CGRect(x: f.minX, y: f.minY, width: f.width, height: v.minY - f.minY)
        case .left: CGRect(x: f.minX, y: f.minY, width: v.minX - f.minX, height: f.height)
        case .right: CGRect(x: v.maxX, y: f.minY, width: f.maxX - v.maxX, height: f.height)
        case nil: nil
        }
    }

    static func previewFrame(icon: CGRect, size: CGSize, edge: DockEdge, screenFrame s: CGRect, gap: CGFloat) -> CGRect {
        var origin: CGPoint
        switch edge {
        case .bottom: origin = CGPoint(x: icon.midX - size.width / 2, y: icon.maxY + gap)
        case .left: origin = CGPoint(x: icon.maxX + gap, y: icon.midY - size.height / 2)
        case .right: origin = CGPoint(x: icon.minX - gap - size.width, y: icon.midY - size.height / 2)
        }
        origin.x = max(s.minX, min(origin.x, s.maxX - size.width))
        origin.y = max(s.minY, min(origin.y, s.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }
}
