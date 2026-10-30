import SwiftUI

struct AgentsTabView: View {
    @State private var model = AgentsUsageModel.shared

    var body: some View {
        let s = model.summary
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UsageFormat.tokens(s.totalTokens))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("tokens this month").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(UsageFormat.cost(s.totalCost, estimated: s.costIsEstimated))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(s.costIsEstimated ? "estimated cost" : "cost").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)

            DailyBarsView(days: s.perDay)

            if s.perModel.isEmpty {
                Text(model.hasLoaded ? "No usage recorded this month" : "Loading usage")
                    .font(.callout).foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(s.perModel) { row in
                    HStack {
                        Text(row.model).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(UsageFormat.tokens(row.tokens)).foregroundStyle(.white.opacity(0.7))
                        Text(UsageFormat.cost(row.cost, estimated: row.estimated))
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.model)
                    .accessibilityValue("\(UsageFormat.tokens(row.tokens)) tokens, \(UsageFormat.cost(row.cost, estimated: row.estimated))")
                }
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.black)
        .preferredColorScheme(.dark)
        .task { await model.refreshWhileVisible() }
    }
}
