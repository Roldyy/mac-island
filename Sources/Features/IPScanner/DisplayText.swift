import Foundation

/// Everything that comes from the network (a Bonjour name, a reverse-DNS answer, a vendor string) is untrusted.
/// This is the one door between such text and the screen, the clipboard and the CSV.
public enum DisplayText {
    public static let defaultMaxLength = 64

    /// Control characters, line and paragraph separators, bidirectional overrides/isolates, zero-width and
    /// invisible format characters are removed (not replaced by spaces: a name must not be able to fake a gap),
    /// the rest is trimmed and cut to `maxLength` characters. Returns nil when nothing visible is left.
    public static func clean(_ raw: String?, maxLength: Int = defaultMaxLength) -> String? {
        guard let raw, maxLength > 0 else { return nil }
        // Bound the work first: a hostile 10 MB name is cut before it is scanned.
        let bounded = raw.unicodeScalars.prefix(maxLength * 4)
        var out = String.UnicodeScalarView()
        for scalar in bounded where !isStripped(scalar) { out.append(scalar) }
        let text = String(out).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxLength))
    }

    static func isStripped(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate: return true
        default: break
        }
        // Whitespace other than the plain space (tabs are controls already; NBSP, em space...) becomes absent.
        if s.properties.isWhitespace && s != " " { return true }
        return false
    }
}
