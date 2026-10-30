import Foundation

/// Parses what the Finder scripts print. Paths are separated by the ASCII record separator so a
/// newline inside a file name cannot split an item. Anything that is not a clean absolute path is dropped.
enum FinderPathParser {
    static let separator: Character = "\u{1E}"

    static func parseSelection(_ raw: String?) -> [URL] {
        guard let raw, !raw.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [URL] = []
        for piece in raw.split(separator: separator, omittingEmptySubsequences: true) {
            guard let path = clean(String(piece)), path != "/", seen.insert(path).inserted else { continue }
            out.append(URL(fileURLWithPath: path))
        }
        return out
    }

    static func parseFolder(_ raw: String?) -> URL? {
        guard let raw, let path = clean(raw.trimmingCharacters(in: .newlines)) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Absolute, no NUL, no `..` component. A trailing slash (folders) is removed, the root stays.
    private static func clean(_ p: String) -> String? {
        guard p.hasPrefix("/"), !p.contains("\u{0}") else { return nil }
        var path = p
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        guard !path.split(separator: "/").contains("..") else { return nil }
        return path
    }
}
