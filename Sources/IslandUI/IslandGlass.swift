import SwiftUI

/// What the glass looks like for a given set of display options. Pure, so tests can pin it.
public struct IslandGlassSpec: Equatable, Sendable {
    /// `false` means an opaque surface (Reduce Transparency).
    public let usesMaterial: Bool
    public let borderWidth: CGFloat
    public let border: IslandAdaptiveColor

    public static func resolve(_ options: IslandDisplayOptions) -> IslandGlassSpec {
        // An opaque surface has no blur to set it off the wallpaper, so it gets the strong outline too.
        let strongBorder = options.increaseContrast || options.reduceTransparency
        return IslandGlassSpec(
            usesMaterial: !options.reduceTransparency,
            borderWidth: options.increaseContrast ? 1.5 : (options.reduceTransparency ? 1 : 0.5),
            border: strongBorder ? IslandPalette.separatorStrong : IslandPalette.separator)
    }
}

private struct IslandGlassModifier: ViewModifier {
    private let display = IslandDisplay()
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let spec = IslandGlassSpec.resolve(display.options)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if spec.usesMaterial {
                    shape.fill(.thinMaterial)
                } else {
                    shape.fill(IslandSurface.solid.color)
                }
            }
            .overlay { shape.strokeBorder(spec.border.color, lineWidth: spec.borderWidth) }
    }
}

public extension View {
    /// Frosted-glass surface: a system material, an opaque surface under Reduce Transparency and a
    /// stronger border under Increase Contrast.
    func islandGlass(cornerRadius: CGFloat = IslandRadius.large) -> some View {
        modifier(IslandGlassModifier(cornerRadius: cornerRadius))
    }
}
