import IslandUI
import SwiftUI

extension ModelFamily {
    var color: Color {
        switch self {
        case .opus: IslandStatus.warning.color
        case .sonnet: IslandPalette.accent.color
        case .haiku: IslandStatus.success.color
        case .other: IslandStatus.neutral.color
        }
    }
}

/// Stacked bars per hour (today) or per day, by model family, with a tokens / cost switch, value axis,
/// date labels and a hover readout (the total and the peak while nothing is hovered).
struct AgentsTrendCard: View {
    enum Metric: String, CaseIterable, Identifiable {
        case tokens, cost
        var id: String { rawValue }
        var title: String { self == .tokens ? AgentsStrings.tokensToggle : AgentsStrings.costToggle }
    }

    let buckets: [DayUsage]
    let hourly: Bool
    let estimated: Bool
    @State private var metric = Metric.tokens
    @State private var hovered: Date?

    private static let chartHeight: CGFloat = 88
    private static let axisWidth: CGFloat = 48

    init(buckets: [DayUsage], hourly: Bool, estimated: Bool, metric: Metric = .tokens) {
        self.buckets = buckets
        self.hourly = hourly
        self.estimated = estimated
        _metric = State(initialValue: metric)
    }

    var body: some View {
        AgentsCardFrame(.trend, trailing: {
            AgentsSegmentedControl(items: Metric.allCases, selection: $metric, title: \.title,
                                   label: AgentsStrings.text("trendCard"))
        }) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                if buckets.allSatisfy({ $0.tokens == 0 }) {
                    Text(AgentsStrings.text("noActivity")).font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                } else {
                    readout
                    chart
                    legend
                }
            }
        }
    }

    // MARK: values

    private func value(_ bucket: DayUsage) -> Double {
        metric == .tokens ? Double(bucket.tokens) : bucket.cost
    }

    private func value(_ share: FamilyShare) -> Double {
        metric == .tokens ? Double(share.tokens) : share.cost
    }

    private func figure(_ amount: Double) -> String {
        metric == .tokens ? UsageFormat.tokens(Int(amount.rounded())) : UsageFormat.cost(amount, estimated: estimated)
    }

    private func label(_ bucket: DayUsage) -> String {
        hourly ? UsageFormat.hour(bucket.day) : UsageFormat.shortDay(bucket.day)
    }

    private func text(_ bucket: DayUsage) -> String {
        let figure = metric == .tokens ? AgentsStrings.format("tokensFormat", UsageFormat.tokens(bucket.tokens))
            : UsageFormat.cost(bucket.cost, estimated: estimated)
        return "\(label(bucket)) · \(figure)"
    }

    private var peakValue: Double { max(buckets.map(value).max() ?? 0, 0.000_001) }

    // MARK: parts

    private var readout: some View {
        let total = buckets.reduce(0) { $0 + value($1) }
        let peak = buckets.max { value($0) < value($1) }
        let summary = [AgentsStrings.fill(constant: AgentsStrings.totalFormat, figure(total)),
                       peak.map { AgentsStrings.fill(constant: AgentsStrings.peakFormat, text($0)) }].compactMap { $0 }.joined(separator: "   ")
        let shown = buckets.first { $0.day == hovered }
        return Text(shown.map(text) ?? summary)
            .font(.islandValue)
            .foregroundStyle(shown == nil ? IslandPalette.textSecondary.color : IslandPalette.textPrimary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var chart: some View {
        HStack(alignment: .top, spacing: IslandSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                axisLabel(figure(peakValue)).offset(y: -6)
                axisLabel(figure(peakValue / 2)).offset(y: Self.chartHeight / 2 - 6)
                axisLabel(figure(0)).offset(y: Self.chartHeight - 6)
            }
            .frame(width: Self.axisWidth, height: Self.chartHeight, alignment: .topTrailing)
            VStack(spacing: IslandSpacing.xs) {
                bars
                dateLabels
            }
        }
        .padding(.top, 6)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text).font(.islandFootnote).monospacedDigit()
            .foregroundStyle(IslandPalette.textTertiary.color)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(height: 12)
    }

    private var bars: some View {
        let peak = peakValue
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                gridLine
                Spacer(minLength: 0)
                gridLine
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: hourly ? 3 : 2) {
                ForEach(buckets) { bucket in
                    VStack(spacing: 0) {
                        ForEach(bucket.shares.reversed(), id: \.family) { share in
                            Rectangle().fill(share.family.color)
                                .frame(height: Self.chartHeight * CGFloat(value(share) / peak))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 2, maxHeight: Self.chartHeight, alignment: .bottom)
                    .opacity(hovered == nil || hovered == bucket.day ? 1 : 0.55)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = bucket.day } else if hovered == bucket.day { hovered = nil }
                    }
                    .help(text(bucket))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(text(bucket))
                }
            }
            Rectangle().fill(IslandPalette.textPrimary.color.opacity(0.35)).frame(height: 1)
        }
        .frame(height: Self.chartHeight, alignment: .bottom)
    }

    private var gridLine: some View {
        Rectangle().fill(IslandPalette.textPrimary.color.opacity(0.10)).frame(height: 1)
    }

    /// First, middle and last bar: enough to read the time axis without crowding it.
    private var dateLabels: some View {
        let first = buckets.first, last = buckets.last
        let middle = buckets.isEmpty ? nil : buckets[buckets.count / 2]
        return ZStack {
            Text(first.map(label) ?? "").frame(maxWidth: .infinity, alignment: .leading)
            Text(middle.map(label) ?? "").frame(maxWidth: .infinity, alignment: .center)
            Text(last.map(label) ?? "").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.islandFootnote).monospacedDigit()
        .foregroundStyle(IslandPalette.textTertiary.color)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        let present = Set(buckets.flatMap(\.shares).filter { $0.tokens > 0 }.map(\.family))
        return HStack(spacing: IslandSpacing.m) {
            ForEach(ModelFamily.allCases.filter(present.contains), id: \.self) { family in
                HStack(spacing: IslandSpacing.xs) {
                    RoundedRectangle(cornerRadius: 2).fill(family.color).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(family.title).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
        .padding(.leading, Self.axisWidth + IslandSpacing.xs)
    }
}
