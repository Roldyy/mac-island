import SwiftUI

/// Value bar for volume and brightness: symbol, bar, percentage.
public struct IslandHUD: View {
    let symbol: String
    let label: String
    let value: Double

    public init(symbol: String, label: String, value: Double) {
        self.symbol = symbol
        self.label = label
        self.value = Self.clamped(value)
    }

    /// NaN and out-of-range values never reach the layout.
    public static func clamped(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }

    public static func percentText(_ value: Double) -> String {
        "\(Int((clamped(value) * 100).rounded()))\u{202F}%"
    }

    public var body: some View {
        HStack(spacing: IslandSpacing.s) {
            Image(systemName: symbol)
                .font(.islandBody)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .frame(width: 20)
                .accessibilityHidden(true)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(IslandPalette.textTertiary.color.opacity(0.3))
                    Capsule()
                        .fill(IslandPalette.accent.color)
                        .frame(width: proxy.size.width * value)
                }
            }
            .frame(height: IslandMetrics.hudBarHeight)
            .islandAnimation(value: value)
            Text(Self.percentText(value))
                .font(.islandValue)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, IslandSpacing.m)
        .padding(.vertical, IslandSpacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Self.percentText(value))
    }
}
