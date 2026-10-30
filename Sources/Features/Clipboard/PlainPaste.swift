import Foundation

enum PlainPaste {
    /// Styles are dropped by only ever reading the string flavour; this normalises that string.
    static func normalize(_ input: String) -> String {
        var s = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u.value {
            case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF: continue          // zero-width, BOM
            case 0x00A0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: out.append(" ")
            case 0x2028, 0x2029: out.append("\n")
            case 0x09, 0x0A: out.append(u)
            case 0x00...0x1F, 0x7F: continue                                 // other controls
            default: out.append(u)
            }
        }
        s = String(out)
        return s.precomposedStringWithCanonicalMapping
    }
}
