import Foundation

/// Parses what the Finder scripts return. Anything that is not a clean absolute path is refused.
enum FinderPathParser {
    /// Reads the list the selection script returns: item 1 is the count Finder reported, the other
    /// items are POSIX paths, one list item each, so no character in a name can start another path.
    /// Refuses (throws) when it is not a list or when the clean paths do not add up to that count.
    static func parseSelection(_ desc: NSAppleEventDescriptor?) throws -> [URL] {
        guard let desc, desc.descriptorType == typeAEList, desc.numberOfItems >= 1,
              let reported = desc.atIndex(1)?.int32Value, reported >= 0,
              desc.atIndex(1)?.descriptorType != typeUnicodeText
        else { throw FinderScriptError.badResult }
        var seen = Set<String>()
        var out: [URL] = []
        if desc.numberOfItems >= 2 {
            for i in 2...desc.numberOfItems {
                guard let raw = desc.atIndex(i)?.stringValue, let path = clean(raw), path != "/",
                      seen.insert(path).inserted else { continue }
                out.append(URL(fileURLWithPath: path))
            }
        }
        // Whatever was dropped (not a path, duplicate) or added changes the count: refuse the whole selection.
        guard out.count == Int(reported), desc.numberOfItems - 1 == Int(reported) else {
            throw FinderScriptError.badResult
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
