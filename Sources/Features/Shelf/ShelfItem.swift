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

    /// lstat based: a symlink counts as present itself, its target is never touched.
    var availability: Availability { ShelfFileCheck.exists(path) ? .available : .missing }

    /// Bookmark first (follows a moved file), then the stored path. nil when nothing exists.
    func resolvedURL() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               ShelfFileCheck.exists(url.path) {
                return url
            }
        }
        guard !path.isEmpty, ShelfFileCheck.exists(path) else { return nil }
        return URL(fileURLWithPath: path)
    }
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
