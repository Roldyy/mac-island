import Foundation

struct PlannedMove: Equatable {
    var source: URL
    var destinationFolder: URL
}

struct MovePlan: Equatable {
    var moves: [PlannedMove]
    var skippedSameFolder: Int
}

/// Validates a batch before any file is touched. Conservative: one unsafe item refuses the batch.
enum MovePlanner {
    static let maxItems = 200

    static func plan(items: [URL], destination: URL, inspector: FileInspecting,
                     confirmedLarge: Bool = false) -> Result<MovePlan, MoveRefusal> {
        guard !items.isEmpty else { return .failure(.noItems) }
        guard inspector.isReadableWritableDirectory(destination) else { return .failure(.destinationUnavailable) }
        if items.count > maxItems && !confirmedLarge { return .failure(.needsConfirmation(count: items.count)) }

        let dest = key(inspector.resolved(destination))
        // Drop items already inside another selected folder: the folder move carries them.
        let roots = items.filter { item in
            !items.contains { other in other != item && item.path.lowercased().hasPrefix(other.path.lowercased() + "/") }
        }

        var moves: [PlannedMove] = []
        var skipped = 0
        for item in roots {
            // A symlink moves as itself, so only a real item can contain its destination.
            if !inspector.isSymlink(item) {
                let own = key(inspector.resolved(item))
                if dest == own || dest.hasPrefix(own + "/") { return .failure(.intoItself) }
            }
            let parent = key(inspector.resolved(item.deletingLastPathComponent()))
            if parent == dest { skipped += 1; continue }
            moves.append(PlannedMove(source: item, destinationFolder: destination))
        }
        guard !moves.isEmpty else { return .failure(.sameFolder) }
        return .success(MovePlan(moves: moves, skippedSameFolder: skipped))
    }

    /// Case-insensitive comparison: on a case-insensitive volume a false match only refuses, never moves.
    private static func key(_ url: URL) -> String { url.path.lowercased() }
}
