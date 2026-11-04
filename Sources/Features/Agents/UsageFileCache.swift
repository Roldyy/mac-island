import Foundation

/// Per-file parse cache keyed by path + size + mtime. A reference type so the value-type source
/// (and copies of it handed to detached tasks) share one cache. Logs only grow, so a bigger file whose
/// first bytes are unchanged is resumed from the last committed newline instead of re-read.
/// The cache can be saved to and restored from disk (`UsageCacheStore`), so a relaunch starts warm.
final class UsageFileCache: @unchecked Sendable {
    struct Key: Equatable {
        var size: Int
        var mtime: Date
    }
    struct Entry {
        var key: Key
        var parse: ClaudeUsageParser.FileParse
        /// First bytes of the committed part: a rewritten file no longer matches and is read again.
        var fingerprint: Data
    }

    static let fingerprintBytes = 256

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var parsed = 0
    private var resumed = 0
    private var restored = false

    /// Total number of file reads (full or resumed) since creation (tests read this).
    var parseCount: Int { lock.withLock { parsed } }

    /// Reads that resumed from a cached offset instead of starting over.
    var resumeCount: Int { lock.withLock { resumed } }

    var isEmpty: Bool { lock.withLock { entries.isEmpty } }

    func entry(for path: String) -> Entry? { lock.withLock { entries[path] } }

    func store(_ parse: ClaudeUsageParser.FileParse, path: String, key: Key, fingerprint: Data, resumedRead: Bool = false) {
        // Streaming logs repeat a message id once per content block; keeping the best copy per file
        // keeps the cache (memory and disk) at the size of the distinct messages.
        var parse = parse
        parse.committed.records = UsageRecord.deduplicated(parse.committed.records)
        lock.withLock {
            if resumedRead { resumed += 1 }
            entries[path] = Entry(key: key, parse: parse, fingerprint: fingerprint)
            parsed += 1
        }
    }

    /// Forget files that were not seen in the last pass (deleted or aged out of the window).
    @discardableResult
    func retain(paths: Set<String>) -> Int {
        lock.withLock {
            let before = entries.count
            entries = entries.filter { paths.contains($0.key) }
            return before - entries.count
        }
    }

    // MARK: disk

    /// Fills an empty cache from `store`, once per cache. True when entries came back. A missing or
    /// corrupt file leaves the cache empty (and is overwritten by the next save).
    @discardableResult
    func restore(from store: UsageCacheStore) -> Bool {
        let already = lock.withLock { () -> Bool in
            if restored { return true }
            restored = true
            return false
        }
        guard !already, let loaded = store.read() else { return false }
        return lock.withLock {
            guard entries.isEmpty else { return false }
            entries = loaded
            return !loaded.isEmpty
        }
    }

    func snapshot() -> [String: Entry] { lock.withLock { entries } }

    /// Every cached record (committed and tail) with the counts a `UsageLoadResult` carries, already merged
    /// across files. Used to show the last known numbers before the folder has even been walked.
    func merged() -> (records: [UsageRecord], malformed: Int, files: Int) {
        let all = snapshot().values
        // One pass and one array: the repeats across files (a resumed session copies its history) are folded as
        // they come, instead of building the full list and then a second deduplicated copy of it.
        var records: [UsageRecord] = []
        var best: [String: Int] = [:]
        var malformed = 0
        func add(_ record: UsageRecord) {
            guard let id = record.messageID else { records.append(record); return }
            if let index = best[id] {
                if record.outputTokens > records[index].outputTokens { records[index] = record }
            } else {
                best[id] = records.count
                records.append(record)
            }
        }
        for entry in all {
            entry.parse.committed.records.forEach(add)
            entry.parse.tail.records.forEach(add)
            malformed += entry.parse.committed.malformedLines + entry.parse.tail.malformedLines
        }
        return (records, malformed, all.count)
    }
}
