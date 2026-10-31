import SwiftUI

/// Every foreground color of the app. Views take these, never a raw `Color`.
public enum IslandPalette {
    public static let textPrimary = IslandAdaptiveColor(light: IslandRGB(white: 0.05), dark: IslandRGB(white: 0.98))
    public static let textSecondary = IslandAdaptiveColor(light: IslandRGB(white: 0.22), dark: IslandRGB(white: 0.82))
    public static let textTertiary = IslandAdaptiveColor(light: IslandRGB(white: 0.30), dark: IslandRGB(white: 0.72))

    public static let accent = IslandAdaptiveColor(light: IslandRGB(0.0, 0.33, 0.78), dark: IslandRGB(0.40, 0.68, 1.0))
    /// Reference blue for the contrast tests only. The prominent button and the switch fill with
    /// `Color.accentColor` (the user's system accent); a white label is checked against this value.
    public static let prominentFill = IslandAdaptiveColor(both: IslandRGB(0.0, 0.36, 0.82))
    public static let destructiveFill = IslandAdaptiveColor(both: IslandRGB(0.72, 0.08, 0.10))
    /// Glyph inside the white switch knob: dark in both schemes, so it never depends on the surface.
    public static let knobGlyph = IslandAdaptiveColor(both: IslandRGB(white: 0.30))
    public static let onFill = IslandAdaptiveColor(both: IslandRGB(white: 1.0))

    /// Separator used when Increase Contrast is on; the plain one is decorative only.
    public static let separatorStrong = IslandAdaptiveColor(light: IslandRGB(white: 0.35), dark: IslandRGB(white: 0.68))
    public static let separator = IslandAdaptiveColor(light: IslandRGB(white: 0.62), dark: IslandRGB(white: 0.40))

    public static let statusNeutral = IslandAdaptiveColor(light: IslandRGB(white: 0.30), dark: IslandRGB(white: 0.78))
    public static let statusInfo = IslandAdaptiveColor(light: IslandRGB(0.0, 0.33, 0.65), dark: IslandRGB(0.40, 0.78, 1.0))
    public static let statusSuccess = IslandAdaptiveColor(light: IslandRGB(0.0, 0.38, 0.12), dark: IslandRGB(0.30, 0.85, 0.45))
    public static let statusWarning = IslandAdaptiveColor(light: IslandRGB(0.50, 0.27, 0.0), dark: IslandRGB(1.0, 0.72, 0.25))
    public static let statusDanger = IslandAdaptiveColor(light: IslandRGB(0.64, 0.0, 0.04), dark: IslandRGB(1.0, 0.62, 0.58))

    /// Opacity of the tint behind a badge. Low enough that the status color still reads at 4.5:1 on it.
    public static let badgeTint = 0.08

    /// The badge background: the status color at `badgeTint` over the surface, per scheme.
    public static func badgeBackground(_ status: IslandStatus, over surface: IslandAdaptiveColor) -> IslandAdaptiveColor {
        func blend(_ fg: IslandRGB, _ bg: IslandRGB) -> IslandRGB {
            IslandRGB(bg.red + (fg.red - bg.red) * badgeTint,
                      bg.green + (fg.green - bg.green) * badgeTint,
                      bg.blue + (fg.blue - bg.blue) * badgeTint)
        }
        let token = Self.status(status)
        return IslandAdaptiveColor(light: blend(token.light, surface.light), dark: blend(token.dark, surface.dark))
    }

    public static func status(_ status: IslandStatus) -> IslandAdaptiveColor {
        switch status {
        case .neutral: statusNeutral
        case .info: statusInfo
        case .success: statusSuccess
        case .warning: statusWarning
        case .danger: statusDanger
        }
    }

    /// Text and icon tokens, all held to the same bar over every surface they can sit on.
    public static let foregroundTokens: [(name: String, color: IslandAdaptiveColor)] = [
        ("textPrimary", textPrimary), ("textSecondary", textSecondary), ("textTertiary", textTertiary),
        ("accent", accent),
        ("statusNeutral", statusNeutral), ("statusInfo", statusInfo), ("statusSuccess", statusSuccess),
        ("statusWarning", statusWarning), ("statusDanger", statusDanger),
    ]

    /// Every pair the contrast tests check. Foregrounds are held to the text bar (4.5), which also
    /// covers icons; the separator is a graphic and gets 3.0.
    public static var contrastPairs: [IslandContrastPair] {
        var pairs: [IslandContrastPair] = []
        let surfaces: [(name: String, color: IslandAdaptiveColor, schemes: [IslandScheme])] = [
            ("verre", IslandSurface.glassReference, [.light, .dark]),
            ("solide", IslandSurface.solid, [.light, .dark]),
            ("encoche", IslandSurface.notchBlackColor, [.dark]),
        ]
        for surface in surfaces {
            for token in foregroundTokens {
                pairs.append(IslandContrastPair(
                    name: "\(token.name) sur \(surface.name)", foreground: token.color,
                    background: surface.color, minimum: IslandContrast.textMinimum, schemes: surface.schemes))
            }
            pairs.append(IslandContrastPair(
                name: "separatorStrong sur \(surface.name)", foreground: separatorStrong,
                background: surface.color, minimum: IslandContrast.largeOrIconMinimum, schemes: surface.schemes))
        }
        // A badge is status-colored text on its own tint, which sits a little off the surface color.
        for status in IslandStatus.allCases {
            for surface in surfaces where surface.name != "encoche" {
                pairs.append(IslandContrastPair(
                    name: "badge \(status.rawValue) sur \(surface.name)", foreground: Self.status(status),
                    background: badgeBackground(status, over: surface.color),
                    minimum: IslandContrast.textMinimum, schemes: surface.schemes))
            }
        }
        pairs.append(IslandContrastPair(
            name: "glyphe sur bouton", foreground: knobGlyph, background: onFill,
            minimum: IslandContrast.largeOrIconMinimum, schemes: [.light, .dark]))
        for (name, fill) in [("prominentFill", prominentFill), ("destructiveFill", destructiveFill)] {
            pairs.append(IslandContrastPair(
                name: "libelle sur \(name)", foreground: onFill, background: fill,
                minimum: IslandContrast.textMinimum, schemes: [.light, .dark]))
        }
        return pairs
    }
}
