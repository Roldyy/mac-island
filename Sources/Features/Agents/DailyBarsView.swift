import IslandUI
import SwiftUI

/// Small token bars (one per day, or per hour for "Aujourd’hui") drawn with plain shapes.
struct DailyBarsView: View {
    let days: [DayUsage]
    var hourly = false

    var body: some View {
        let peak = max(days.map(\.tokens).max() ?? 1, 1)
        IslandCard {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(IslandPalette.accent.color)
                        .frame(height: max(3, 48 * CGFloat(day.tokens) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 48, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hourly ? "Tokens par heure" : "Tokens par jour")
        .accessibilityValue(days.isEmpty ? "Aucune donnée"
            : "\(days.count) \(hourly ? "heures" : "jours"), maximum \(UsageFormat.tokens(peak)) tokens")
    }
}
