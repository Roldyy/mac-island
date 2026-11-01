import CoreGraphics

/// Pure geometry of the island, kept free of AppKit so it can be tested without a screen.
/// Coordinates are AppKit's: origin bottom-left, so "top" means `maxY`.
public struct NotchGeometry: Equatable {
    public static let pillWidth: CGFloat = 200
    public static let pillHeight: CGFloat = 32

    /// Black margin a wing keeps next to the notch when it has something to show (a 3 pt rim). A side with nothing
    /// to show has no wing at all, so the island at rest is exactly the notch. Everything beyond the rim is the
    /// content's: each wing is exactly as wide as what it shows.
    public static let baseWing: CGFloat = 3
    /// Most a wing may add beyond `baseWing` (64 pt each side), so the island never stretches across the bar.
    public static let maxWingExtent: CGFloat = 76
    /// One point of wing in a width stand-in (a figure space), see `AmbientMetrics.measuringItem`.
    public static let measureUnit: Character = "\u{2007}"
    public static let minOpenHeight: CGFloat = 120

    public let frame: CGRect
    public let hasNotch: Bool

    /// Resting frame: the notch itself, or a black pill at top center when the screen has none.
    /// `auxLeft` / `auxRight` are `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
    public static func idle(
        screenFrame: CGRect, safeAreaTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = auxLeft, let right = auxRight, right.minX > left.maxX {
            let width = right.minX - left.maxX
            let frame = CGRect(
                x: left.maxX, y: screenFrame.maxY - safeAreaTop, width: width, height: safeAreaTop)
            return NotchGeometry(frame: frame, hasNotch: true)
        }
        let frame = CGRect(
            x: screenFrame.midX - pillWidth / 2, y: screenFrame.maxY - pillHeight,
            width: pillWidth, height: pillHeight)
        return NotchGeometry(frame: frame, hasNotch: false)
    }

    /// Open frame: same top-center anchor, clamped so it never leaves the screen.
    public static func expanded(from idle: NotchGeometry, size: CGSize, screenFrame: CGRect) -> CGRect {
        let width = min(size.width, screenFrame.width)
        let height = min(size.height, screenFrame.height)
        var x = idle.frame.midX - width / 2
        x = max(screenFrame.minX, min(x, screenFrame.maxX - width))
        return CGRect(x: x, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Width an item needs beyond `baseWing`: glyph, a gap and an estimate of the text, capped.
    /// The estimate is deliberately rough (11 pt text, about 6.5 pt per character).
    public static func wingExtent(for item: CompactItem?) -> CGFloat {
        guard let item else { return 0 }
        if let text = item.text, !text.isEmpty, text.allSatisfy({ $0 == measureUnit }) {
            return min(CGFloat(text.count), maxWingExtent)
        }
        var width: CGFloat = 14 + 8
        if let text = item.text, !text.isEmpty {
            width += 4 + CGFloat(min(text.count, 14)) * 6.5
        }
        return min(width.rounded(.up), maxWingExtent)
    }

    /// The larger of the two sides' extents. Kept for callers that only need "how wide is the widest wing".
    public static func wingExtent(for layout: ActivityLayout) -> CGFloat {
        max(wingExtent(for: layout.leading), wingExtent(for: layout.trailing))
    }

    /// Width of each wing of a layout, measured from the notch edge: 0 for a side with nothing to show,
    /// otherwise `baseWing` plus what its own item needs. A dot alone sits on a base wing on the right.
    public static func wingWidths(for layout: ActivityLayout) -> (leading: CGFloat, trailing: CGFloat) {
        func width(_ item: CompactItem?) -> CGFloat { item == nil ? 0 : baseWing + wingExtent(for: item) }
        let trailing = width(layout.trailing)
        return (width(layout.leading), trailing == 0 && layout.dot != nil ? baseWing : trailing)
    }

    /// Closed frame with a wing of its own width on each side of the idle frame. `leading` and `trailing` are
    /// the full wing widths (0 allowed, capped at `baseWing + maxWingExtent`). The notch stays where it is:
    /// the frame starts `leading` points left of the idle frame and ends `trailing` points right of it, so with
    /// nothing to show it is exactly the idle frame. Kept on screen.
    public static func closedFrame(
        from idle: NotchGeometry, leading: CGFloat, trailing: CGFloat, screenFrame: CGRect
    ) -> CGRect {
        var left = max(0, min(leading, baseWing + maxWingExtent))
        var right = max(0, min(trailing, baseWing + maxWingExtent))
        // A screen without a notch has a pill, not a hole to keep in place: it stays centred, both sides equal.
        if !idle.hasNotch {
            left = max(left, right, baseWing)
            right = left
        }
        let width = min(idle.frame.width + left + right, screenFrame.width)
        var x = idle.frame.minX - left
        x = max(screenFrame.minX, min(x, screenFrame.maxX - width))
        return CGRect(x: x, y: idle.frame.minY, width: width, height: idle.frame.height)
    }

    /// Closed frame of a layout (see `wingWidths`).
    public static func closedFrame(from idle: NotchGeometry, layout: ActivityLayout, screenFrame: CGRect) -> CGRect {
        let wings = wingWidths(for: layout)
        return closedFrame(from: idle, leading: wings.leading, trailing: wings.trailing, screenFrame: screenFrame)
    }

    /// Wing widths actually left once the closed frame is kept on screen, measured from the idle frame.
    public static func wings(of closed: CGRect, around idle: NotchGeometry) -> (leading: CGFloat, trailing: CGFloat) {
        (max(0, idle.frame.minX - closed.minX), max(0, closed.maxX - idle.frame.maxX))
    }

    /// A tab may ask for any height; the panel keeps it between a usable minimum and the screen.
    public static func clampedOpenHeight(_ height: CGFloat, screenFrame: CGRect) -> CGFloat {
        max(min(minOpenHeight, screenFrame.height), min(height, screenFrame.height))
    }
}
