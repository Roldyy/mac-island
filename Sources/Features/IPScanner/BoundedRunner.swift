import Foundation

/// Runs async work over a list with at most `limit` jobs in flight, optionally spacing out the starts.
/// Cooperative: when the surrounding task is cancelled, every running job is cancelled and `CancellationError` is thrown.
enum BoundedRunner {
    static func forEach<Item: Sendable, Output: Sendable>(
        _ items: [Item], limit: Int, spacing: Duration = .zero,
        work: @escaping @Sendable (Item) async -> Output,
        onResult: (Item, Output) throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let width = max(1, limit)
        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var next = 0
            while next < min(width, items.count) {
                if next > 0, spacing > .zero { try await Task.sleep(for: spacing) }
                let index = next
                next += 1
                group.addTask { (index, await work(items[index])) }
            }
            while let (index, output) = try await group.next() {
                try Task.checkCancellation()
                try onResult(items[index], output)
                if next < items.count {
                    if spacing > .zero { try await Task.sleep(for: spacing) }
                    let following = next
                    next += 1
                    group.addTask { (following, await work(items[following])) }
                }
            }
        }
    }
}
