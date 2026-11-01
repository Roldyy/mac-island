import Foundation

/// Quotes a path for zsh and bash. Pure.
enum ShellEscape {
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")

    /// Plain when every character is shell-safe, single quotes otherwise (a quote inside becomes `'\''`).
    /// A control character (newline, tab) cannot sit raw in a typed line, so such a path uses `$'...'`
    /// with escapes. Unicode stays as is, inside quotes.
    static func quote(_ path: String) -> String {
        if path.isEmpty { return "''" }
        if path.allSatisfy({ safe.contains($0) }) { return path }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
            var out = "$'"
            for scalar in path.unicodeScalars {
                switch scalar {
                case "\\": out += "\\\\"
                case "'": out += "\\'"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                default:
                    if scalar.value < 0x20 || scalar.value == 0x7f {
                        out += "\\x" + String(format: "%02x", scalar.value)
                    } else {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
            return out + "'"
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Quoted paths separated by a space, with a trailing space so the next word does not stick to them.
    static func argumentList(_ paths: [String]) -> String {
        paths.map(quote).joined(separator: " ") + " "
    }
}
