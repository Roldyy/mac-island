import SwiftUI

/// Icon, message and an optional action, for a panel with nothing to show.
public struct IslandEmptyState: View {
    let symbol: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(symbol: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: IslandSpacing.s) {
            Image(systemName: symbol)
                .font(.system(size: IslandType.body * 2))
                .foregroundStyle(IslandPalette.textSecondary.color)
                .accessibilityHidden(true)
            Text(message)
                .font(.islandBody)
                .foregroundStyle(IslandPalette.textSecondary.color)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(IslandButtonStyle())
            }
        }
        .padding(IslandSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
