import Foundation

/// Sanitisers for every string that comes from outside (session files, hook JSON).
public enum ClaudeText {
    public static let maxFolderLength = 64

    /// Last path component only, control characters dropped, bounded. Never a full path.
    public static func folderName(fromCwd cwd: String) -> String {
        guard let last = cwd.split(separator: "/", omittingEmptySubsequences: true).last else { return "" }
        let clean = last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(clean.prefix(maxFolderLength)))
    }

    /// `[A-Za-z0-9_-]{1,64}`: invalid characters are dropped, the rest truncated. Empty result = nil.
    public static func sanitizedID(_ raw: String) -> String? {
        var out = ""
        for u in raw.unicodeScalars where isIDScalar(u) {
            out.unicodeScalars.append(u)
            if out.utf8.count == 64 { break }
        }
        return out.isEmpty ? nil : out
    }

    public static func isIDScalar(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D: true
        default: false
        }
    }

    /// Entry point label (`cli`, `claude-vscode`): same alphabet as ids, up to 32 characters, else nil.
    public static func entrypoint(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.utf8.count <= 32, raw.unicodeScalars.allSatisfy(isIDScalar) else { return nil }
        return raw
    }

    /// ASCII digits only (Swift's `\d` also matches other scripts).
    public static func isASCIIDigits(_ s: Substring) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }
}
