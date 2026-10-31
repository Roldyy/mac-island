import IslandUI
import SwiftUI

/// The 13-week heatmap (7 rows x 13 columns) and its three figures.
struct AgentsActivityCard: View {
    let heatmap: UsageHeatmap
    let stats: HeatmapStats

    private static let gap: CGFloat = 3

    var body: some View {
        AgentsCardFrame(.activity) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                grid
                HStack(alignment: .top, spacing: IslandSpacing.m) {
                    figure(AgentsStrings.text("streak"), "\(stats.streak)")
                    figure(AgentsStrings.text("activeDays"), "\(stats.activeDays)")
                    figure(AgentsStrings.text("busiestDay"), stats.busiest.map { UsageFormat.shortDay($0.day) } ?? "—")
                }
            }
        }
    }

    private var grid: some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(heatmap.columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: Self.gap) {
                    ForEach(column) { cell in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(cell))
                            .aspectRatio(1, contentMode: .fit)
                            .help(tooltip(cell))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(tooltip(cell))
                    }
                }
            }
        }
    }

    /// Level 0 = a faint cell; 1...4 = the accent at growing strength. Future days are not drawn.
    private func color(_ cell: HeatCell) -> Color {
        if cell.isFuture { return .clear }
        guard cell.level > 0 else { return IslandPalette.textPrimary.color.opacity(0.08) }
        return IslandPalette.accent.color.opacity(0.25 + 0.2 * Double(cell.level))
    }

    private func tooltip(_ cell: HeatCell) -> String {
        guard !cell.isFuture else { return UsageFormat.shortDay(cell.day) }
        return "\(UsageFormat.shortDay(cell.day)) · \(AgentsStrings.format("tokensFormat", UsageFormat.tokens(cell.tokens)))"
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            Text(value).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color).monospacedDigit()
            Text(label).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
