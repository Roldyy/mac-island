import SwiftUI

/// Compact summary for the closed island: month tokens and cost.
struct AgentsIdleView: View {
    @State private var model = AgentsUsageModel.shared

    init() {}

    var body: some View {
        let s = model.summary
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.7))
            Text(UsageFormat.tokens(s.totalTokens))
            Text(UsageFormat.cost(s.totalCost, estimated: s.costIsEstimated))
                .foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI usage this month")
        .accessibilityValue("\(UsageFormat.tokens(s.totalTokens)) tokens, \(UsageFormat.cost(s.totalCost, estimated: s.costIsEstimated))")
        .task { await model.refresh() }
    }
}
