import IslandUI
import SwiftUI

/// The 13-week heatmap (7 rows x 13 columns) with weekday and month labels, a legend and its three figures.
struct AgentsActivityCard: View {
    let heatmap: UsageHeatmap
    let stats: HeatmapStats
    var calendar = UsageFormat.calendar

    private static let cell: CGFloat = 17
    private static let gap: CGFloat = 4
    private static let labelWidth: CGFloat = 30

    var body: some View {
        AgentsCardFrame(.activity) {
            HStack(alignment: .top, spacing: IslandSpacing.xl) {
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    monthLabels
                    HStack(alignment: .top, spacing: IslandSpacing.xs) {
                        weekdayLabels
                        grid
                    }
                    legend
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: IslandSpacing.m) {
                    figure(AgentsStrings.text("streak"), "\(stats.streak)")
                    figure(AgentsStrings.text("activeDays"), "\(stats.activeDays)")
                    figure(AgentsStrings.text("busiestDay"), stats.busiest.map { UsageFormat.shortDay($0.day) } ?? "—")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: grid

    private var grid: some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(heatmap.columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: Self.gap) {
                    ForEach(column) { cell in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(cell))
                            .frame(width: Self.cell, height: Self.cell)
                            .help(tooltip(cell))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(tooltip(cell))
                    }
                }
            }
        }
    }

    /// Short names of the rows the calendar lists, first weekday on top; only every other row is named.
    private var weekdayLabels: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return VStack(alignment: .trailing, spacing: Self.gap) {
            ForEach(0..<UsageHeatmap.daysPerWeek, id: \.self) { row in
                Text(row % 2 == 0 ? symbols[(calendar.firstWeekday - 1 + row) % 7] : "")
                    .font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
                    .lineLimit(1)
                    .frame(width: Self.labelWidth, height: Self.cell, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    /// The month name sits over the first column that starts in that month.
    private var monthLabels: some View {
        let names = Self.monthNames(heatmap.columns.map { $0.first?.day }, calendar: calendar)
        return HStack(spacing: Self.gap) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Color.clear.frame(width: Self.cell, height: 14)
                    .overlay(alignment: .leading) {
                        Text(name).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
                            .fixedSize()
                    }
            }
        }
        .padding(.leading, Self.labelWidth + IslandSpacing.xs)
        .accessibilityHidden(true)
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
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(levelColor(level))
                    .frame(width: 11, height: 11)
            }
            Text(AgentsStrings.more).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
        }
        .padding(.leading, Self.labelWidth + IslandSpacing.xs)
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

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(IslandPalette.textPrimary.color).monospacedDigit()
            Text(label).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }
}
