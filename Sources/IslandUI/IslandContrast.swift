import Foundation

/// WCAG 2.x contrast, pure. Text needs 4.5, large text and icons 3.0.
public enum IslandContrast {
    public static let textMinimum = 4.5
    public static let largeOrIconMinimum = 3.0

    public static func luminance(_ rgb: IslandRGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    /// Ratio between 1 and 21, order of the arguments does not matter.
    public static func ratio(_ first: IslandRGB, _ second: IslandRGB) -> Double {
        let a = luminance(first), b = luminance(second)
        let (lighter, darker) = a >= b ? (a, b) : (b, a)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// A foreground that must stay readable over a surface.
public struct IslandContrastPair: Sendable {
    public let name: String
    public let foreground: IslandAdaptiveColor
    public let background: IslandAdaptiveColor
    public let minimum: Double
    /// Schemes where the pair really occurs (the notch band only exists on dark).
    public let schemes: [IslandScheme]

    public func ratio(in scheme: IslandScheme) -> Double {
        IslandContrast.ratio(foreground.rgb(for: scheme), background.rgb(for: scheme))
    }
}
