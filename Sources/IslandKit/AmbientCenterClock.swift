import IslandUI
import SwiftUI

/// The clock in the fixed center slot of the pill: the time at 12 pt with tabular digits so it never jitters,
/// then, when the pill has room, the short date in the quieter 11 pt style.
struct AmbientCenterClock: View {
    let item: AmbientIndicator

    static var timeFont: Font {
        .system(size: IslandType.caption, weight: .semibold, design: .rounded).monospacedDigit()
    }

    static var dateFont: Font {
        .system(size: IslandType.minimumSize, weight: .medium, design: .rounded)
    }

    var body: some View {
        HStack(spacing: AmbientMetrics.centerDetailGap) {
            if let text = item.text {
                Text(text)
                    .font(Self.timeFont)
                    .foregroundStyle(IslandPalette.textPrimary.color)
            }
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(Self.dateFont)
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .transition(.opacity)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel())
    }
}
