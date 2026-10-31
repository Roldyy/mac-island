import SwiftUI

/// A short status label. The symbol and the word carry the meaning; color only reinforces it.
public struct IslandBadge: View {
    let text: String
    let status: IslandStatus

    public init(_ text: String, status: IslandStatus = .neutral) {
        self.text = text
        self.status = status
    }

    /// Status word plus text, unless the text already is the status word ("Attention : Attention").
    public static func spokenLabel(_ text: String, status: IslandStatus) -> String {
        text.compare(status.label, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            ? text : "\(status.label) : \(text)"
    }

    public var body: some View {
        HStack(spacing: IslandSpacing.xs) {
            Image(systemName: status.symbol)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.islandFootnote.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(status.color)
        .padding(.horizontal, IslandSpacing.s)
        .padding(.vertical, IslandSpacing.xxs + 1)
        .background(status.color.opacity(IslandPalette.badgeTint), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(text, status: status))
    }
}
