import CoreGraphics

/// Where the pointer opens (or keeps open) the island, as pure geometry in global screen coordinates (origin
/// bottom-left, the main display first, other displays at their own offsets).
public enum IslandHoverRegion {
    /// Points added above the top edge: the pointer stops on the very last row, which is the frame's `maxY`.
    public static let topReach: CGFloat = 2

    /// The closed island (notch plus the wings that have something to show) while closed, the whole panel while
    /// open, always reaching the top edge.
    public static func zone(closedFrame: CGRect, panelFrame: CGRect, isOpen: Bool) -> CGRect {
        var zone = isOpen ? panelFrame : closedFrame
        zone.size.height += topReach
        return zone
    }

    /// The zone in the panel's own coordinates, cut to the panel: a tracking area outside its window is never hit.
    /// Empty when the zone and the panel do not meet.
    public static func trackingRect(zone: CGRect, panelFrame: CGRect) -> CGRect {
        let local = zone.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
        let bounds = CGRect(origin: .zero, size: panelFrame.size)
        let clipped = local.intersection(bounds)
        return clipped.isNull ? .zero : clipped
    }
}
