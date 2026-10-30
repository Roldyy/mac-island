import Foundation

protocol FileMoving: Sendable {
    func move(from: URL, to: URL) throws
}

/// FileManager.moveItem renames the item itself: a symlink moves as a link, never its target,
/// and it throws instead of overwriting an existing destination.
struct FileManagerMover: FileMoving {
    func move(from: URL, to: URL) throws {
        try FileManager.default.moveItem(at: from, to: to)
    }
}

struct MoveReport: Equatable {
    var moved: Int
    var failedSources: [URL]
    var skipped: Int
    var failed: Int { failedSources.count }
    var isPartial: Bool { moved > 0 && failed > 0 }
}

enum MoveExecutor {
    /// Moves one item at a time. The destination name is chosen right before each move, so two items
    /// with the same name and a file that appeared meanwhile never collide. One failure never stops the rest.
    static func run(_ plan: MovePlan, inspector: FileInspecting, mover: FileMoving) -> MoveReport {
        var report = MoveReport(moved: 0, failedSources: [], skipped: plan.skippedSameFolder)
        for move in plan.moves {
            var done = false
            for _ in 0..<3 where !done {
                guard let target = CollisionNamer.unique(name: move.source.lastPathComponent,
                                                         in: move.destinationFolder, exists: inspector.exists) else { break }
                do {
                    try mover.move(from: move.source, to: target)
                    done = true
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    continue   // lost a race for that name: pick the next one
                } catch {
                    break
                }
            }
            if done { report.moved += 1 } else { report.failedSources.append(move.source) }
        }
        return report
    }
}
