import Foundation

/// Pure list operations on the shelf.
enum ShelfItems {
    /// Adds references (never copies). Dedupes by standardized path; symlinks get no bookmark
    /// because a bookmark would resolve to the target.
    static func add(_ urls: [URL], to items: [ShelfItem], now: Date,
                    makeBookmark: (URL) -> Data?) -> [ShelfItem] {
        var out = items
        var known = Set(items.map(\.path))
        for url in urls where url.isFileURL {
            let std = url.standardizedFileURL
            guard !known.contains(std.path) else { continue }
            known.insert(std.path)
            let bookmark = ShelfFileCheck.isSymlink(std.path) ? nil : makeBookmark(std)
            out.append(ShelfItem(path: std.path, bookmark: bookmark, addedAt: now))
        }
        return out
    }

    static func remove(_ id: UUID, from items: [ShelfItem]) -> [ShelfItem] {
        items.filter { $0.id != id }
    }
}
