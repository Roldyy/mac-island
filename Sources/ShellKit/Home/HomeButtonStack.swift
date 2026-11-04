import CoreGraphics
import IslandUI

/// The decisions behind the round-button stacks, pure so they are testable without a view: when a side column (or the
/// bottom row) must scroll instead of growing, and how much room each one has.
public enum HomeButtonStack {
    /// Length of the soft fade at each end of a scrolling stack, which is also the margin the content rests behind.
    public static let fade: CGFloat = 12
    /// Gap between two round buttons.
    public static let spacing: CGFloat = IslandSpacing.m
    /// Where the Roldy mark sits in the bottom row: `leading 26` + `width 58`, plus a breathing gap.
    static let markReserve: CGFloat = 26 + 58 + 8

    public static func contentLength(count: Int, item: CGFloat, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * item + CGFloat(count - 1) * spacing
    }

    /// True when `count` buttons do not fit `available` points along the stack's axis.
    public static func needsScroll(count: Int, item: CGFloat, spacing: CGFloat, available: CGFloat) -> Bool {
        contentLength(count: count, item: item, spacing: spacing) > available
    }

    /// Room of a side column: from the first button's top (under the band) to the foot of the body.
    public static func sideAvailable(bodyHeight: CGFloat, band: CGFloat) -> CGFloat {
        max(bodyHeight - band - HomeGeometry.bandGap, 0)
    }

    /// Room of the bottom row: the panel width, minus the corner the Roldy mark takes on both sides (kept symmetric).
    public static func bottomAvailable(panelWidth: CGFloat) -> CGFloat {
        max(panelWidth - 2 * markReserve, 0)
    }
}
