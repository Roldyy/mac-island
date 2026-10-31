import SwiftUI

/// The single button style of the app.
public struct IslandButtonStyle: ButtonStyle {
    public enum Variant: Sendable, CaseIterable {
        case standard, prominent, destructive
    }

    let variant: Variant

    public init(_ variant: Variant = .standard) { self.variant = variant }

    public func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, variant: variant)
    }
}

private struct IslandButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: IslandButtonStyle.Variant
    @Environment(\.isEnabled) private var isEnabled
    private let display = IslandDisplay()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous)
        configuration.label
            .font(.islandCaptionEmphasis)
            .foregroundStyle(foreground)
            .padding(.horizontal, IslandSpacing.m)
            .frame(minHeight: IslandMetrics.controlHeight)
            .background(fill.opacity(configuration.isPressed ? 0.75 : 1), in: shape)
            .overlay {
                if variant == .standard || display.options.increaseContrast {
                    shape.strokeBorder(border, lineWidth: display.options.increaseContrast ? 1.5 : 0.5)
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .islandAnimation(value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .standard: IslandPalette.textPrimary.color
        case .prominent, .destructive: IslandPalette.onFill.color
        }
    }

    private var fill: Color {
        switch variant {
        case .standard: IslandPalette.textPrimary.color.opacity(0.10)
        case .prominent: IslandPalette.prominentFill.color
        case .destructive: IslandPalette.destructiveFill.color
        }
    }

    private var border: Color {
        display.options.increaseContrast ? IslandPalette.separatorStrong.color : IslandPalette.separator.color
    }
}

public extension ButtonStyle where Self == IslandButtonStyle {
    static var island: IslandButtonStyle { IslandButtonStyle() }
    static var islandProminent: IslandButtonStyle { IslandButtonStyle(.prominent) }
    static var islandDestructive: IslandButtonStyle { IslandButtonStyle(.destructive) }
}
