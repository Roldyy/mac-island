import SwiftUI

/// Small daily token bars drawn with plain shapes.
struct DailyBarsView: View {
    let days: [DayUsage]

    var body: some View {
        let peak = max(days.map(\.tokens).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(days) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.85))
                    .frame(height: max(3, 48 * CGFloat(day.tokens) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 48, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily token usage this month")
        .accessibilityValue(days.isEmpty ? "No data"
            : "\(days.count) days, peak \(UsageFormat.tokens(peak)) tokens")
    }
}
