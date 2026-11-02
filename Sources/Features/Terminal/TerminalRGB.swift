import AppKit
import SwiftTerm
import SwiftUI

/// One sRGB colour, components always finite and inside 0...1. Alpha is dropped: a terminal paints opaque cells.
struct TerminalRGB: Equatable, Sendable, Codable {
    let red: Double
    let green: Double
    let blue: Double

    /// For trusted constants and values already validated: a non-finite component becomes 0, the rest is clamped.
    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    init(red8: Int, green8: Int, blue8: Int) {
        self.init(Double(red8) / 255, Double(green8) / 255, Double(blue8) / 255)
    }

    /// Untrusted components: nil when any is NaN or infinite, otherwise clamped to 0...1.
    static func validated(_ red: Double, _ green: Double, _ blue: Double) -> TerminalRGB? {
        guard red.isFinite, green.isFinite, blue.isFinite else { return nil }
        return TerminalRGB(red, green, blue)
    }

    /// Converts any colour space to sRGB; nil for a colour that has no RGB reading (a pattern) or a non-finite one.
    init?(color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        guard let value = Self.validated(Double(r), Double(g), Double(b)) else { return nil }
        self = value
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let r = try container.decode(Double.self, forKey: .red)
        let g = try container.decode(Double.self, forKey: .green)
        let b = try container.decode(Double.self, forKey: .blue)
        guard let value = Self.validated(r, g, b) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Composante non finie"))
        }
        self = value
    }

    var hex: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    var swiftUIColor: SwiftUI.Color { SwiftUI.Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    /// SwiftTerm stores 16-bit components.
    var terminalColor: SwiftTerm.Color {
        func word(_ value: Double) -> UInt16 { UInt16((value * 65535).rounded()) }
        return SwiftTerm.Color(red: word(red), green: word(green), blue: word(blue))
    }
}
