import SwiftUI

/// Surfaces under the content. The glass itself is a system material; the reference value is the
/// worst plausible blend over a wallpaper, used only by the contrast tests.
public enum IslandSurface {
    /// The top of the island stays solid black behind the hardware notch.
    public static let notchBlack = Color.black
    public static let notchBlackColor = IslandAdaptiveColor(both: IslandRGB(white: 0))

    /// Opaque fallback for Reduce Transparency.
    public static let solid = IslandAdaptiveColor(light: IslandRGB(white: 0.95), dark: IslandRGB(white: 0.195))
    /// Lightest dark blend and darkest light blend the material can give.
    public static let glassReference = IslandAdaptiveColor(light: IslandRGB(white: 0.88), dark: IslandRGB(white: 0.24))
}
