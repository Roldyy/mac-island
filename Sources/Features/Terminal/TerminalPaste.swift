import Foundation

/// Bytes sent to the shell for a paste or a drop. Pure.
enum TerminalPaste {
    private static let bracketStart: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e]
    private static let bracketEnd: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]

    /// Line breaks become carriage returns, which is what Return sends, so a pasted block runs as typed.
    /// Under bracketed paste every ESC is dropped first: a text carrying the end marker could otherwise
    /// close the paste early and run what follows as commands.
    static func payload(text: String, bracketed: Bool) -> [UInt8] {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\r")
        normalized = normalized.replacingOccurrences(of: "\n", with: "\r")
        var body = Array(normalized.utf8)
        guard bracketed else { return body }
        body.removeAll { $0 == 0x1b }
        return bracketStart + body + bracketEnd
    }

    /// What the pasteboard offers, in order of preference: copied files become their quoted paths
    /// (a Finder copy also carries the file names as text, which would be worse), then plain text.
    static func content(fileURLs: [URL], string: String?) -> String? {
        let paths = fileURLs.filter(\.isFileURL).map(\.path)
        if !paths.isEmpty { return ShellEscape.argumentList(paths) }
        guard let string, !string.isEmpty else { return nil }
        return string
    }
}
