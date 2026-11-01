import CoreGraphics
import Foundation

/// Pure widths of the closed island's indicators. The estimates are rough on purpose (11 pt rounded
/// semibold with tabular digits) and slightly generous: too much room reads as breathing space, too little
/// as a clipped value. The island's frame itself is still `NotchGeometry`'s.
public enum AmbientMetrics {
    public static let glyphSize: CGFloat = 18
    public static let iconGap: CGFloat = 4
    public static let elementGap: CGFloat = 8
    /// Space kept free at each end of a wing.
    public static let wingPadding: CGFloat = 10
    /// Gap between the two groups of the pill, where the separator sits.
    public static let groupGap: CGFloat = 14
    /// Free space at each end of the pill.
    public static let pillPadding: CGFloat = 14
    /// A title or an alert wider than this scrolls (or is cut under Reduce Motion).
    public static let maxTextWidth: CGFloat = 72

    public static func charWidth(_ c: Character) -> CGFloat {
        switch c {
        case "0"..."9": 7.7
        case "%": 11
        case ":", ".", ",", "'", "’", "|", "!", "i", "l", "j", "I": 4
        case " ": 3.8
        case "m", "w", "M", "W": 11.4
        case _ where c.isUppercase: 8.6
        default: 7.2
        }
    }

    public static func textWidth(_ text: String) -> CGFloat {
        text.reduce(0) { $0 + charWidth($1) }
    }

    /// What the clock of an indicator reserves: `00:00` under an hour, `0:00:00` from then on, so the width
    /// does not change every ten minutes.
    public static func clockPlaceholder(since: Date, now: Date) -> String {
        now.timeIntervalSince(since) >= 3600 ? "0:00:00" : "00:00"
    }

    /// Seconds until the clock needs one more digit group; nil once it already has them.
    public static func secondsUntilClockWidens(since: Date, now: Date) -> TimeInterval? {
        let left = since.addingTimeInterval(3600).timeIntervalSince(now)
        return left > 0 ? left : nil
    }

    /// Width of the visible text (the clock, the value or the title), capped at `maxTextWidth`.
    public static func textSlot(_ item: AmbientIndicator, now: Date) -> CGFloat {
        if let since = item.clockSince { return textWidth(clockPlaceholder(since: since, now: now)) }
        guard let text = item.text, !text.isEmpty else { return 0 }
        return min(textWidth(text), maxTextWidth)
    }

    /// Width of the bar between a glyph and its value (the volume).
    public static let barWidth: CGFloat = 34
    /// Clear space between the center clock and each side group.
    public static let centerGap: CGFloat = 10
    /// The center clock is drawn at body size (13 pt) so it reads at a glance; its digits are 13/11 wider.
    public static let centerScale: CGFloat = 13.0 / 11.0
    /// Gap between the time and the date in the center slot.
    public static let centerDetailGap: CGFloat = 8

    public static func elementWidth(_ item: AmbientIndicator, now: Date) -> CGFloat {
        let slot = textSlot(item, now: now)
        var width: CGFloat = item.glyph == .none ? 0 : glyphSize
        if item.bar != nil { width += (width > 0 ? iconGap : 0) + barWidth }
        if slot > 0 { width += (width > 0 ? iconGap : 0) + slot }
        return width
    }

    /// What the center clock reserves: the time at 13 pt, then the date when it is shown.
    public static func centerWidth(_ item: AmbientIndicator?) -> CGFloat {
        guard let item else { return 0 }
        var width = textWidth(item.text ?? "") * centerScale + 2
        if let detail = item.detail, !detail.isEmpty { width += centerDetailGap + textWidth(detail) }
        return width.rounded(.up)
    }

    /// Most a side group may take next to the center clock before the pill reaches its widest.
    public static func pillSideLimit(center: AmbientIndicator?) -> CGFloat {
        let widest = NotchGeometry.pillWidth + 2 * (NotchGeometry.baseWing + NotchGeometry.maxWingExtent)
        return max(0, (widest - centerWidth(center) - 2 * pillPadding) / 2 - centerGap)
    }

    public static func groupWidth(_ items: [AmbientIndicator], now: Date) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + elementWidth($1, now: now) } + CGFloat(items.count - 1) * elementGap
    }

    /// A wing that is too narrow loses the text of its last element, then the element itself. Never empties it.
    public static func fitted(_ items: [AmbientIndicator], width: CGFloat, now: Date) -> [AmbientIndicator] {
        var out = items
        while !out.isEmpty, groupWidth(out, now: now) + 2 * wingPadding > width {
            if let index = out.lastIndex(where: { $0.text != nil || $0.clockSince != nil }) {
                out[index].text = nil
                out[index].clockSince = nil
                continue
            }
            if out.count > 1 { out.removeLast() } else { break }
        }
        return out
    }

    // MARK: - Extent

    /// How far each wing must grow beyond `NotchGeometry.baseWing` around a hardware notch: both wings share it
    /// so the notch stays centered. 0...`NotchGeometry.maxWingExtent`.
    public static func notchedExtent(_ content: ClosedIslandContent, now: Date) -> CGFloat {
        let need = max(groupWidth(content.leading, now: now), groupWidth(content.trailing, now: now))
        guard need > 0 else { return 0 }
        return clampExtent(need + 2 * wingPadding - NotchGeometry.baseWing)
    }

    /// How far each side must grow beyond `NotchGeometry.baseWing` on a screen without a notch, where both groups
    /// sit side by side in the middle of the pill (so most of the time it does not grow at all).
    public static func pillExtent(_ content: ClosedIslandContent, now: Date, pillWidth: CGFloat = NotchGeometry.pillWidth) -> CGFloat {
        let lead = groupWidth(content.leading, now: now), trail = groupWidth(content.trailing, now: now)
        if let center = content.center {
            // Three zones, symmetric around the clock: both sides reserve the wider side's room, so the clock
            // stays exactly in the middle even when only one side has something to show.
            let side = max(lead, trail)
            let need = centerWidth(center) + (side > 0 ? 2 * (side + centerGap) : 0) + 2 * pillPadding
            return clampExtent((need - (pillWidth + 2 * NotchGeometry.baseWing)) / 2)
        }
        guard lead + trail > 0 else { return 0 }
        let need = lead + trail + (lead > 0 && trail > 0 ? groupGap : 0) + 2 * pillPadding
        let base = pillWidth + 2 * NotchGeometry.baseWing
        return clampExtent((need - base) / 2)
    }

    public static func extent(_ content: ClosedIslandContent, notched: Bool, now: Date) -> CGFloat {
        notched ? notchedExtent(content, now: now) : pillExtent(content, now: now)
    }

    static func clampExtent(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value.rounded(.up), 0), NotchGeometry.maxWingExtent)
    }

    /// A stand-in the panel can measure: `NotchGeometry.wingExtent(for:)` reads an item's text length, so an
    /// item of the right length makes the panel as wide as the strip needs. Nil when no growth is needed.
    public static func measuringItem(forExtent extent: CGFloat) -> CompactItem? {
        guard extent > 0 else { return nil }
        if extent <= 22 { return CompactItem(symbol: "circle") }
        let characters = min(14, max(1, Int(((extent - 26) / 6.5).rounded(.up))))
        // Figure spaces: they are text to the measure, nothing to the eye (the item is never drawn).
        return CompactItem(symbol: "", text: String(repeating: "\u{2007}", count: characters))
    }
}
