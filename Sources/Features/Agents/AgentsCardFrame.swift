import IslandUI
import SwiftUI

extension AgentsCard {
    /// Accent tint of the card's header glyph (palette tokens only).
    var tint: Color {
        switch self {
        case .limits, .trend: IslandPalette.accent.color
        case .spend: IslandStatus.success.color
        case .live: IslandStatus.info.color
        case .models: IslandStatus.warning.color
        case .projects, .activity: IslandPalette.accent.color
        case .resets: IslandStatus.neutral.color
        }
    }
}

/// Header (tinted symbol + title) over the card content, in the standard glass card.
struct AgentsCardFrame<Content: View>: View {
    let card: AgentsCard
    let content: Content

    init(_ card: AgentsCard, @ViewBuilder content: () -> Content) {
        self.card = card
        self.content = content()
    }

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                HStack(spacing: IslandSpacing.xs) {
                    Image(systemName: card.symbol)
                        .font(.islandBodyEmphasis)
                        .foregroundStyle(card.tint)
                        .accessibilityHidden(true)
                    Text(card.title)
                        .font(.islandBodyEmphasis)
                        .foregroundStyle(IslandPalette.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                }
                content
            }
        }
    }
}

/// A line of secondary text used across the cards.
struct AgentsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.islandFootnote)
            .foregroundStyle(IslandPalette.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
