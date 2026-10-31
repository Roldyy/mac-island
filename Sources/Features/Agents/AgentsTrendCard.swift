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

/// Stacked bars per hour (today) or per day, by model family, with a tokens / cost switch and a hover readout.
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

    private static let chartHeight: CGFloat = 72

    var body: some View {
        AgentsCardFrame(.trend) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                Picker(AgentsStrings.text("trendCard"), selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if buckets.allSatisfy({ $0.tokens == 0 }) {
                    Text(AgentsStrings.text("noActivity")).font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                } else {
                    readout
                    bars
                    legend
                }
            }
        }
    }

    private func value(_ bucket: DayUsage) -> Double {
        metric == .tokens ? Double(bucket.tokens) : bucket.cost
    }

    private func value(_ share: FamilyShare) -> Double {
        metric == .tokens ? Double(share.tokens) : share.cost
    }

    private func text(_ bucket: DayUsage) -> String {
        let label = hourly ? UsageFormat.hour(bucket.day) : UsageFormat.shortDay(bucket.day)
        let figure = metric == .tokens ? AgentsStrings.format("tokensFormat", UsageFormat.tokens(bucket.tokens))
            : UsageFormat.cost(bucket.cost, estimated: estimated)
        return "\(label) · \(figure)"
    }

    private var readout: some View {
        let shown = buckets.first { $0.day == hovered }
        return Text(shown.map(text) ?? " ")
            .font(.islandValue)
            .foregroundStyle(IslandPalette.textSecondary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var bars: some View {
        let peak = max(buckets.map(value).max() ?? 0, 0.000_001)
        return HStack(alignment: .bottom, spacing: hourly ? 2 : 1) {
            ForEach(buckets) { bucket in
                VStack(spacing: 0) {
                    ForEach(bucket.shares.reversed(), id: \.family) { share in
                        Rectangle().fill(share.family.color)
                            .frame(height: Self.chartHeight * CGFloat(value(share) / peak))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 2, maxHeight: Self.chartHeight, alignment: .bottom)
                .background(alignment: .bottom) {
                    Rectangle().fill(IslandPalette.textPrimary.color.opacity(0.10)).frame(height: 2)
                }
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = bucket.day } else if hovered == bucket.day { hovered = nil }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text(bucket))
            }
        }
        .frame(height: Self.chartHeight, alignment: .bottom)
    }

    private var legend: some View {
        let present = Set(buckets.flatMap(\.shares).filter { $0.tokens > 0 }.map(\.family))
        return HStack(spacing: IslandSpacing.m) {
            ForEach(ModelFamily.allCases.filter(present.contains), id: \.self) { family in
                HStack(spacing: IslandSpacing.xs) {
                    Circle().fill(family.color).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(family.title).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
    }
}
