import IslandUI
import SwiftUI

/// One indicator: glyph, then its value. The Claude clock ticks once a second in its own timeline, so the rest
/// of the strip never redraws for it.
struct AmbientElementView: View {
    let item: AmbientIndicator
    /// Tests freeze the clock here; the app leaves it nil and the clock runs.
    let clock: Date?
    let pulsePreview: Double?

    var body: some View {
        HStack(spacing: AmbientMetrics.iconGap) {
            if item.glyph != .none { AmbientGlyphView(item: item) }
            if let bar = item.bar { AmbientBar(fill: bar, color: item.status.color) }
            value
        }
        .fixedSize()
        .modifier(AmbientPulse(color: item.status.color, isUrgent: item.isUrgent, preview: pulsePreview))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var tint: Color {
        item.status == .warning || item.status == .danger ? item.status.color : IslandPalette.textPrimary.color
    }

    private var label: String {
        item.accessibilityLabel(clock: item.clockSince.map { ElapsedTime.text(since: $0, now: clock ?? Date()) })
    }

    @ViewBuilder
    private var value: some View {
        if let since = item.clockSince {
            if let clock {
                clockText(since: since, now: clock)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    clockText(since: since, now: timeline.date)
                }
            }
        } else if let text = item.text, !text.isEmpty {
            AmbientValueText(text: text, slot: AmbientMetrics.textSlot(item, now: clock ?? Date()), tint: tint)
        }
    }

    private func clockText(since: Date, now: Date) -> some View {
        Text(ElapsedTime.text(since: since, now: now))
            .font(AmbientValueText.font)
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(width: AmbientMetrics.textSlot(item, now: now), alignment: .leading)
    }
}
