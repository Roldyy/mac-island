import IslandUI
import SwiftUI

/// Compact summary for the closed island: tokens and cost of the selected period.
struct AgentsIdleView: View {
    @State private var model = AgentsUsageModel.shared

    init() {}

    var body: some View {
        let s = model.summary
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(IslandPalette.textSecondary.color)
            Text(UsageFormat.tokens(s.totalTokens))
            Text(UsageFormat.cost(s.totalCost, estimated: s.costIsEstimated))
                .foregroundStyle(IslandPalette.textSecondary.color)
        }
        .font(.islandCaptionEmphasis)
        .monospacedDigit()
        .foregroundStyle(IslandPalette.textPrimary.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consommation IA \(model.period.phrase)")
        .accessibilityValue("\(UsageFormat.exactTokens(s.totalTokens)) tokens, \(UsageFormat.cost(s.totalCost, estimated: s.costIsEstimated))")
        .task { await model.refresh() }
    }
}
