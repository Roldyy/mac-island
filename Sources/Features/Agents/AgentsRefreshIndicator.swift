import IslandUI
import SwiftUI

/// "Actualisation…": a pulsing dot and a quiet word next to the title while the logs are being read.
struct AgentsRefreshIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: IslandSpacing.xs + 1) {
            Image(systemName: "circle.fill").font(.system(size: 6))
                .foregroundStyle(IslandPalette.accent.color)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text(AgentsStrings.refreshing).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentsStrings.refreshing)
    }
}
