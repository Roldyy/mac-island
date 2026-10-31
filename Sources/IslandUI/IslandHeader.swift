import SwiftUI

/// The single section header.
public struct IslandHeader: View {
    let title: String
    let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            Text(title)
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.islandCaption)
                    .foregroundStyle(IslandPalette.textSecondary.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
