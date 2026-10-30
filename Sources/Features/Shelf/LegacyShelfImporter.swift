import Foundation

/// Tolerant reader for the old app's `shelfItems` value. Only the empty shape was observed
/// (Data holding `[]`), so strings, dictionaries and bookmark data are all accepted in JSON or
/// property-list form. Bookmarks do not transfer between apps: resolve by path when they fail.
enum LegacyShelfImporter {
    private static let pathKeys = ["path", "filePath", "url", "urlString", "fileURL", "file"]
    private static let bookmarkKeys = ["bookmark", "bookmarkData", "bookmarkdata", "data"]

    static func parse(_ data: Data) -> [ShelfItem] {
        guard let array = decodeArray(data) else { return [] }
        var items: [ShelfItem] = []
        var seen = Set<String>()
        let now = Date()
        for element in array {
            guard let (path, bookmark) = entry(from: element), ShelfFileCheck.exists(path) else { continue }
            let std = URL(fileURLWithPath: path).standardizedFileURL.path
            guard seen.insert(std).inserted else { continue }
            items.append(ShelfItem(path: std, bookmark: bookmark, addedAt: now))
        }
        return items
    }

    private static func decodeArray(_ data: Data) -> [Any]? {
        guard !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [Any] { return json }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [Any] {
            return plist
        }
        return nil
    }

    private static func entry(from element: Any) -> (String, Data?)? {
        var pathString: String?
        var bookmarkData: Data?
        switch element {
        case let s as String:
            pathString = s
        case let d as Data:
            bookmarkData = d
        case let dict as [String: Any]:
            for key in pathKeys { if let s = dict[key] as? String { pathString = s; break } }
            for key in bookmarkKeys {
                if let d = dict[key] as? Data { bookmarkData = d; break }
                if let s = dict[key] as? String, let d = Data(base64Encoded: s) { bookmarkData = d; break }
            }
        default:
            return nil
        }
        let normalizedPath = pathString.flatMap(normalize)
        var resolvedBookmark: Data?
        var bookmarkPath: String?
        if let bookmarkData {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               ShelfFileCheck.exists(url.path) {
                resolvedBookmark = bookmarkData
                bookmarkPath = url.path
            }
        }
        guard let path = normalizedPath.flatMap({ ShelfFileCheck.exists($0) ? $0 : nil }) ?? bookmarkPath else {
            return nil
        }
        // Keep the bookmark only when it still points at the chosen path.
        return (path, bookmarkPath == path ? resolvedBookmark : nil)
    }

    private static func normalize(_ s: String) -> String? {
        if s.hasPrefix("file://") { return URL(string: s).flatMap { $0.isFileURL ? $0.path : nil } }
        return s.hasPrefix("/") ? s : nil
    }
}
