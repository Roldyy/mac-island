import Foundation

/// What a profile file carried, before the gaps are filled from the default theme.
struct TerminalRawColors: Equatable {
    static let ansiCount = 16
    static let minimumColors = 8

    var ansi: [TerminalRGB?] = Array(repeating: nil, count: ansiCount)
    var foreground: TerminalRGB?
    var background: TerminalRGB?
    var cursor: TerminalRGB?
    var selection: TerminalRGB?
    var name: String?
    var fontName: String?
    var fontSize: Double?

    /// Valid colours found, the 16 ANSI slots and the four special ones together.
    var validCount: Int {
        ansi.compactMap { $0 }.count + [foreground, background, cursor, selection].compactMap { $0 }.count
    }

    /// Fills every gap from the default theme (a missing cursor follows the foreground).
    func resolved(fallbackName: String, now: Date = Date()) -> TerminalColorProfile {
        let fg = foreground ?? TerminalColorProfile.defaultForeground
        let fallback = TerminalColorProfile.sanitizedName(fallbackName)
        return TerminalColorProfile(
            id: UUID(),
            name: TerminalColorProfile.sanitizedName(name ?? fallbackName, fallback: fallback),
            ansi: (0..<Self.ansiCount).map { ansi[$0] ?? TerminalColorProfile.defaultAnsi[$0] },
            foreground: fg,
            background: background ?? TerminalColorProfile.defaultBackground,
            cursor: cursor ?? fg,
            selection: selection ?? TerminalColorProfile.defaultSelection,
            fontName: fontName,
            fontSize: fontSize,
            importedAt: now)
    }
}
