import SwiftUI
import AppKit

/// Pure sRGB triplet, 0...1. Kept apart from `Color` so contrast can be computed in tests.
public struct IslandRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(white: Double) { self.init(white, white, white) }
}

public enum IslandScheme: CaseIterable, Sendable {
    case light, dark
}

/// One color, two explicit values. No system dynamic color: the contrast tests need the numbers.
public struct IslandAdaptiveColor: Equatable, Sendable {
    public let light: IslandRGB
    public let dark: IslandRGB

    public init(light: IslandRGB, dark: IslandRGB) {
        self.light = light
        self.dark = dark
    }

    public init(both value: IslandRGB) { self.init(light: value, dark: value) }

    public func rgb(for scheme: IslandScheme) -> IslandRGB {
        scheme == .light ? light : dark
    }

    public var color: Color {
        let light = self.light, dark = self.dark
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}
