import Foundation

/// A reference to a file on the shelf. Never the content: a path plus optional bookmark data.
struct ShelfItem: Codable, Equatable, Identifiable {
    enum Availability { case available, missing }

    var id: UUID = UUID()
    var path: String
    var bookmark: Data?
    var addedAt: Date

    init(id: UUID = UUID(), path: String, bookmark: Data?, addedAt: Date) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.addedAt = addedAt
    }

    /// Shown name: last path component of the stored path, never of a resolved symlink target.
    var displayName: String { URL(fileURLWithPath: path).lastPathComponent }

    /// Same resolution as drag and reveal (bookmark first). lstat based: a symlink counts as present
    /// itself, its target is never touched.
    var availability: Availability { resolve() == nil ? .missing : .available }

    /// Resolves the item once: the bookmark first (it follows a moved file), then the stored path.
    /// `item` carries the path (and a refreshed bookmark when stale) the bookmark points to now, so
    /// callers can drive name, icon, reveal and drag from one answer. nil when nothing exists.
    func resolve() -> ResolvedShelfItem? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               ShelfFileCheck.exists(url.path) {
                // The OS prefers the old path: a different file that landed there must not pass for
                // the shelved one. Judged only when the bookmark carries the file identity.
                guard Self.isSameFile(url, as: bookmark) else { return nil }
                var updated = self
                if !Self.samePlace(path, url.path) { updated.path = url.standardizedFileURL.path }
                if stale, let fresh = Self.makeBookmark(url) { updated.bookmark = fresh }
                return ResolvedShelfItem(item: updated, url: url)
            }
        }
        guard !path.isEmpty, ShelfFileCheck.exists(path) else { return nil }
        return ResolvedShelfItem(item: self, url: URL(fileURLWithPath: path))
    }

    /// Bookmark that also records the file identity, so a look-alike at the old path is detected.
    static func makeBookmark(_ url: URL) -> Data? {
        try? url.bookmarkData(includingResourceValuesForKeys: [.fileResourceIdentifierKey], relativeTo: nil)
    }

    private static func isSameFile(_ url: URL, as bookmark: Data) -> Bool {
        guard let recorded = URL.resourceValues(forKeys: [.fileResourceIdentifierKey],
                                                fromBookmarkData: bookmark)?.fileResourceIdentifier,
              !(recorded is NSNull),
              let now = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
        else { return true }
        return recorded.isEqual(now)
    }

    func resolvedURL() -> URL? { resolve()?.url }

    /// /var vs /private/var and "." segments must not count as a move.
    private static func samePlace(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: a).resolvingSymlinksInPath().path == URL(fileURLWithPath: b).resolvingSymlinksInPath().path
    }
}

struct ResolvedShelfItem: Equatable {
    var item: ShelfItem
    var url: URL
}

enum ShelfFileCheck {
    static func exists(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var st = stat()
        return lstat(path, &st) == 0
    }

    static func isSymlink(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }
}
