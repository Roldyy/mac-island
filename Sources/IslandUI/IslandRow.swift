import SwiftUI

/// One line of a list: optional symbol, title, optional subtitle, optional status, trailing control.
public struct IslandRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let status: IslandStatus?
    let trailing: Trailing

    public init(
        _ title: String, subtitle: String? = nil, symbol: String? = nil, status: IslandStatus? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.status = status
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: IslandSpacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.islandBody)
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                Text(title)
                    .font(.islandBody)
                    .foregroundStyle(IslandPalette.textPrimary.color)
                if let subtitle {
                    Text(subtitle)
                        .font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
            Spacer(minLength: IslandSpacing.s)
            if let status {
                Image(systemName: status.symbol)
                    .font(.islandCaption)
                    .foregroundStyle(status.color)
                    .accessibilityLabel(status.label)
            }
            trailing
        }
        .frame(minHeight: IslandMetrics.controlHeight)
        .accessibilityElement(children: .contain)
    }
}

public extension IslandRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, status: IslandStatus? = nil) {
        self.init(title, subtitle: subtitle, symbol: symbol, status: status) { EmptyView() }
    }
}
