import Foundation

/// A complete colour scheme for the island terminal: 16 ANSI colours, foreground, background, cursor, selection,
/// and optionally the font the profile asked for. Every colour is present: what a file did not carry
/// was filled from the default theme when it was imported.
struct TerminalColorProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var ansi: [TerminalRGB]
    var foreground: TerminalRGB
    var background: TerminalRGB
    var cursor: TerminalRGB
    var selection: TerminalRGB
    var fontName: String?
    var fontSize: Double?
    var importedAt: Date

    static let maxNameLength = 60
    static let fallbackName = "Profil importé"

    private static let defaultAnsiBytes: [(Int, Int, Int)] = [
        (0, 0, 0), (194, 54, 33), (37, 188, 36), (173, 173, 39), (73, 46, 225), (211, 56, 211), (51, 187, 200), (203, 204, 205),
        (129, 131, 131), (252, 57, 31), (49, 231, 34), (234, 236, 35), (88, 51, 255), (249, 53, 248), (20, 240, 240), (233, 235, 235),
    ]

    /// Terminal.app's own palette, the one the island terminal shows without a profile.
    static let defaultAnsi: [TerminalRGB] = defaultAnsiBytes.map { TerminalRGB(red8: $0.0, green8: $0.1, blue8: $0.2) }
    static let defaultForeground = TerminalRGB(0.88, 0.88, 0.88)
    static let defaultBackground = TerminalRGB(0.06, 0.06, 0.06)
    static let defaultSelection = TerminalRGB(0.16, 0.34, 0.78)

    /// Strips control and invisible formatting characters (bidi overrides included), collapses blanks, caps the length.
    static func sanitizedName(_ raw: String, fallback: String = fallbackName) -> String {
        let visible = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: false
            default: true
            }
        }
        var text = String(String.UnicodeScalarView(visible))
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        text = limitedMarks(text)
        if text.count > maxNameLength { text = String(text.prefix(maxNameLength)) }
        text = cappedScalarsAndBytes(text).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? fallback : text
    }

    static let maxNameScalars = maxNameLength * 4
    static let maxNameBytes = 256
    /// Accents need one or two combining marks; a longer run is a stack of them (Zalgo) and one Character
    /// can hold any number, so the Character cap alone does not bound the size.
    static let maxCombiningRun = 2

    private static func isCombining(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    private static func limitedMarks(_ text: String) -> String {
        var run = 0
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isCombining(scalar) {
                run += 1
                if run > maxCombiningRun { continue }
            } else {
                run = 0
            }
            kept.append(scalar)
        }
        return String(kept)
    }

    /// Cuts at a scalar boundary once either the scalar cap or the UTF-8 byte cap is reached.
    private static func cappedScalarsAndBytes(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        var bytes = 0
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            if kept.count >= maxNameScalars || bytes + size > maxNameBytes { break }
            kept.append(scalar)
            bytes += size
        }
        return String(kept)
    }

    /// Same colours and font, whatever the name, id and date: used to avoid listing one file twice.
    func sameScheme(as other: TerminalColorProfile) -> Bool {
        ansi == other.ansi && foreground == other.foreground && background == other.background
            && cursor == other.cursor && selection == other.selection && fontName == other.fontName
    }
}
