import IslandUI
import SwiftUI

/// The 13-week heatmap (7 rows x 13 columns) with weekday and month labels and a legend. The cells grow to
/// fill the width; the three figures sit beside it when there is room, under it otherwise.
struct AgentsActivityCard: View {
    let heatmap: UsageHeatmap
    let stats: HeatmapStats
    var calendar = UsageFormat.calendar

    private static let gap: CGFloat = 4
    private static let labelWidth: CGFloat = 30
    private static let maxCell: CGFloat = 24

    var body: some View {
        AgentsCardFrame(.activity) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: IslandSpacing.xl) {
                    heat.frame(minWidth: 280)
                    figures(vertical: true).frame(width: 130, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: IslandSpacing.m) {
                    heat
                    figures(vertical: false)
                }
            }
        }
    }

    private var heat: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            grid
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: grid

    /// Month names over the columns, weekday names down the side, square cells that share the width.
    private var grid: some View {
        let names = Self.monthNames(heatmap.columns.map { $0.first?.day }, calendar: calendar)
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
            GridRow {
                Color.clear.frame(width: Self.labelWidth, height: 14)
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Color.clear.frame(maxWidth: .infinity).frame(height: 14)
                        .overlay(alignment: .leading) {
                            Text(name).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color).fixedSize()
                        }
                }
            }
            .accessibilityHidden(true)
            ForEach(0..<UsageHeatmap.daysPerWeek, id: \.self) { row in
                GridRow {
                    Text(row % 2 == 0 ? symbols[(calendar.firstWeekday - 1 + row) % 7] : "")
                        .font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
                        .lineLimit(1)
                        .frame(width: Self.labelWidth, alignment: .trailing)
                        .accessibilityHidden(true)
                    ForEach(Array(heatmap.columns.enumerated()), id: \.offset) { _, column in
                        if row < column.count { cellView(column[row]) } else { Color.clear }
                    }
                }
            }
        }
    }

    private func cellView(_ cell: HeatCell) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(cell))
            .frame(maxWidth: Self.maxCell)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .help(tooltip(cell))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tooltip(cell))
    }

    /// One entry per column: the month abbreviation where it changes, "" elsewhere. A label that would
    /// sit right next to another one is dropped.
    static func monthNames(_ firstDays: [Date?], calendar: Calendar, locale: Locale = UsageFormat.locale) -> [String] {
        var names: [String] = []
        var previousMonth: Int?
        var lastLabelled = -3
        for (index, day) in firstDays.enumerated() {
            guard let day else { names.append(""); continue }
            let month = calendar.component(.month, from: day)
            defer { previousMonth = month }
            guard month != previousMonth, index - lastLabelled >= 3 else { names.append(""); continue }
            names.append(Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                          timeZone: calendar.timeZone).month(.abbreviated).format(day))
            lastLabelled = index
        }
        return names
    }

    private var legend: some View {
        HStack(spacing: IslandSpacing.xs) {
            Text(AgentsStrings.less).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(levelColor(level)).frame(width: 12, height: 12)
            }
            Text(AgentsStrings.more).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
    }

    /// Level 0 = a faint cell; 1...4 = the accent at growing strength. Future days are not drawn.
    private func color(_ cell: HeatCell) -> Color {
        cell.isFuture ? .clear : levelColor(cell.level)
    }

    private func levelColor(_ level: Int) -> Color {
        guard level > 0 else { return IslandPalette.textPrimary.color.opacity(0.10) }
        return IslandPalette.accent.color.opacity(0.30 + 0.175 * Double(level))
    }

    private func tooltip(_ cell: HeatCell) -> String {
        guard !cell.isFuture else { return UsageFormat.shortDay(cell.day) }
        return "\(UsageFormat.shortDay(cell.day)) · \(AgentsStrings.format("tokensFormat", UsageFormat.tokens(cell.tokens)))"
    }

    // MARK: figures

    @ViewBuilder private func figures(vertical: Bool) -> some View {
        let items: [(String, String)] = [(AgentsStrings.text("streak"), "\(stats.streak)"),
                                         (AgentsStrings.text("activeDays"), "\(stats.activeDays)"),
                                         (AgentsStrings.text("busiestDay"), stats.busiest.map { UsageFormat.shortDay($0.day) } ?? "—")]
        if vertical {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                ForEach(items, id: \.0) { AgentsStatTile(value: $0.1, label: $0.0) }
            }
        } else {
            HStack(alignment: .top, spacing: IslandSpacing.s) {
                ForEach(items, id: \.0) { AgentsStatTile(value: $0.1, label: $0.0) }
            }
        }
    }
}
