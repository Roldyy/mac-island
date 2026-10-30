import CoreGraphics

/// Pure geometry of the island, kept free of AppKit so it can be tested without a screen.
/// Coordinates are AppKit's: origin bottom-left, so "top" means `maxY`.
public struct NotchGeometry: Equatable {
    public static let pillWidth: CGFloat = 200
    public static let pillHeight: CGFloat = 32

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
}
