import CoreGraphics

/// Pure geometry of the island, kept free of AppKit so it can be tested without a screen.
/// Coordinates are AppKit's: origin bottom-left, so "top" means `maxY`.
public struct NotchGeometry: Equatable {
    public static let pillWidth: CGFloat = 200
    public static let pillHeight: CGFloat = 32

    /// Black margin on each side of the notch at rest: room to hover and to see the island exist.
    public static let baseWing: CGFloat = 16
    /// Most a wing may add beyond `baseWing`, so a long title never stretches the island across the bar.
    public static let maxWingExtent: CGFloat = 96
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
        var width: CGFloat = 14 + 8
        if let text = item.text, !text.isEmpty {
            width += 4 + CGFloat(min(text.count, 14)) * 6.5
        }
        return min(width.rounded(.up), maxWingExtent)
    }

    /// Both wings share one extent so the notch stays centered. A dot alone adds nothing: it sits on the base wing.
    public static func wingExtent(for layout: ActivityLayout) -> CGFloat {
        max(wingExtent(for: layout.leading), wingExtent(for: layout.trailing))
    }

    /// Closed frame: the idle frame plus the base wings plus `wingExtent`, kept on screen.
    public static func closedFrame(from idle: NotchGeometry, wingExtent: CGFloat, screenFrame: CGRect) -> CGRect {
        let grow = baseWing + max(0, min(wingExtent, maxWingExtent))
        let width = min(idle.frame.width + 2 * grow, screenFrame.width)
        var x = idle.frame.midX - width / 2
        x = max(screenFrame.minX, min(x, screenFrame.maxX - width))
        return CGRect(x: x, y: idle.frame.minY, width: width, height: idle.frame.height)
    }

    /// A tab may ask for any height; the panel keeps it between a usable minimum and the screen.
    public static func clampedOpenHeight(_ height: CGFloat, screenFrame: CGRect) -> CGFloat {
        max(min(minOpenHeight, screenFrame.height), min(height, screenFrame.height))
    }
}
