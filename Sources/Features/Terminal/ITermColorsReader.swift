import AppKit
import Foundation

/// Reads an iTerm2 `.itermcolors` property list: plain dictionaries of numbers, nothing is decoded as an object.
enum ITermColorsReader {
    static func read(_ root: Any) -> TerminalRawColors? {
        guard let dict = root as? [String: Any] else { return nil }
        var raw = TerminalRawColors()
        for index in 0..<TerminalRawColors.ansiCount { raw.ansi[index] = color(dict["Ansi \(index) Color"]) }
        raw.foreground = color(dict["Foreground Color"])
        raw.background = color(dict["Background Color"])
        raw.cursor = color(dict["Cursor Color"])
        raw.selection = color(dict["Selection Color"])
        return raw
    }

    static func color(_ value: Any?) -> TerminalRGB? {
        guard let dict = value as? [String: Any],
              let r = number(dict["Red Component"]), let g = number(dict["Green Component"]),
              let b = number(dict["Blue Component"]),
              let rgb = TerminalRGB.validated(r, g, b) else { return nil }
        let space = (dict["Color Space"] as? String)?.lowercased() ?? "srgb"
        let native: NSColor
        switch space {
        case "p3", "display p3", "displayp3": native = NSColor(displayP3Red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        case "calibrated": native = NSColor(calibratedRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        case "device": native = NSColor(deviceRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        default: return rgb
        }
        return TerminalRGB(color: native)
    }

    /// A plist number; a boolean (also an NSNumber) is not one.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}
