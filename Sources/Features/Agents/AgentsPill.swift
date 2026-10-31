import IslandUI
import SwiftUI

/// A small rounded label: one line, never wraps, a symbol so the tint is never the only signal.
struct AgentsPill: View {
    let text: String
    var symbol: String?
    var tint: Color = IslandPalette.textSecondary.color

    var body: some View {
        HStack(spacing: IslandSpacing.xs) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: IslandType.minimumSize, weight: .semibold)).accessibilityHidden(true)
            }
            Text(text).font(.islandCaptionEmphasis).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, IslandSpacing.s)
        .frame(height: 22)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5) }
        .fixedSize()
    }
}

/// A value over its label inside a faint tile: the "stat chip" of the spend card and the heatmap.
struct AgentsStatTile: View {
    let value: String
    let label: String
    var symbol: String?
    var tint: Color = IslandPalette.textPrimary.color

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.75)
            HStack(spacing: IslandSpacing.xs) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: IslandType.minimumSize)).accessibilityHidden(true)
                }
                Text(label).font(.islandFootnote).lineLimit(1)
            }
            .foregroundStyle(IslandPalette.textSecondary.color)
        }
        .padding(.horizontal, IslandSpacing.s + 2).padding(.vertical, IslandSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IslandPalette.textPrimary.color.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: IslandRadius.small + 2, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
