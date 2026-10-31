import SwiftUI

/// A short status label. The symbol and the word carry the meaning; color only reinforces it.
public struct IslandBadge: View {
    let text: String
    let status: IslandStatus

    public init(_ text: String, status: IslandStatus = .neutral) {
        self.text = text
        self.status = status
    }

    public var body: some View {
        HStack(spacing: IslandSpacing.xs) {
            Image(systemName: status.symbol)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.islandFootnote.weight(.semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, IslandSpacing.s)
        .padding(.vertical, IslandSpacing.xxs + 1)
        .background(status.color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.label) : \(text)")
    }
}
