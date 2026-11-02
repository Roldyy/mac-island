import AppKit
import Foundation

/// Reads a Terminal.app `.terminal` profile. Its colours and font are NSKeyedArchiver blobs: each is decoded
/// with secure coding restricted to ONE class (NSColor, or NSFont), so a blob that names any other class fails
/// closed instead of instantiating it. Only the colour components and the font name and size are kept.
enum TerminalAppProfileReader {
    static let maxBlobBytes = 64 * 1024

    private static let ansiKeys = [
        "ANSIBlackColor", "ANSIRedColor", "ANSIGreenColor", "ANSIYellowColor",
        "ANSIBlueColor", "ANSIMagentaColor", "ANSICyanColor", "ANSIWhiteColor",
        "ANSIBrightBlackColor", "ANSIBrightRedColor", "ANSIBrightGreenColor", "ANSIBrightYellowColor",
        "ANSIBrightBlueColor", "ANSIBrightMagentaColor", "ANSIBrightCyanColor", "ANSIBrightWhiteColor",
    ]

    static func read(_ root: Any) -> TerminalRawColors? {
        guard let dict = root as? [String: Any] else { return nil }
        var raw = TerminalRawColors()
        for (index, key) in ansiKeys.enumerated() { raw.ansi[index] = color(dict[key]) }
        raw.foreground = color(dict["TextColor"])
        raw.background = color(dict["BackgroundColor"])
        raw.cursor = color(dict["CursorColor"])
        raw.selection = color(dict["SelectionColor"])
        raw.name = dict["name"] as? String
        if let font = font(dict["Font"]) {
            raw.fontName = font.name
            raw.fontSize = font.size
        }
        return raw
    }

    static func color(_ value: Any?) -> TerminalRGB? {
        guard let data = blob(value),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else { return nil }
        return TerminalRGB(color: color)
    }

    static func font(_ value: Any?) -> (name: String, size: Double)? {
        guard let data = blob(value),
              let font = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: data) else { return nil }
        let name = TerminalColorProfile.sanitizedName(font.fontName, fallback: "")
        let size = Double(font.pointSize)
        guard !name.isEmpty, size.isFinite, (1...200).contains(size) else { return nil }
        return (name, size)
    }

    private static func blob(_ value: Any?) -> Data? {
        guard let data = value as? Data, !data.isEmpty, data.count <= maxBlobBytes else { return nil }
        return data
    }
}
