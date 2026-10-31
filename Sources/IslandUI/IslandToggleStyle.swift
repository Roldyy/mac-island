import SwiftUI

/// The single switch style of the app: a real switch (track and knob), the label on the left.
/// State is shown by knob position and a glyph in the knob, never by color alone.
public struct IslandToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        IslandToggleBody(configuration: configuration)
    }
}

private struct IslandToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    private let display = IslandDisplay()

    var body: some View {
        let size = IslandMetrics.switchSize
        let knob = size.height - 4
        let isOn = configuration.isOn
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: IslandSpacing.m) {
                configuration.label
                    .font(.islandBody)
                    .foregroundStyle(IslandPalette.textPrimary.color)
                Spacer(minLength: IslandSpacing.s)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? IslandPalette.prominentFill.color : IslandPalette.textTertiary.color.opacity(0.35))
                    Capsule()
                        .strokeBorder(
                            display.options.increaseContrast ? IslandPalette.separatorStrong.color : IslandPalette.separator.color,
                            lineWidth: display.options.increaseContrast ? 1.5 : 0.5)
                    Circle()
                        .fill(IslandPalette.onFill.color)
                        .frame(width: knob, height: knob)
                        .overlay {
                            Image(systemName: isOn ? "checkmark" : "minus")
                                .font(.system(size: IslandType.minimumSize, weight: .bold))
                                .foregroundStyle(isOn ? IslandPalette.prominentFill.color : IslandPalette.separatorStrong.color)
                        }
                        .padding(2)
                }
                .frame(width: size.width, height: size.height)
                .islandAnimation(value: isOn)
            }
            .frame(minHeight: IslandMetrics.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "activé" : "désactivé")
    }
}

public extension ToggleStyle where Self == IslandToggleStyle {
    static var island: IslandToggleStyle { IslandToggleStyle() }
}
