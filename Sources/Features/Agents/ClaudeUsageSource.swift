import Foundation

/// Per-file parse cache keyed by path + size + mtime. A reference type so the value-type source
/// (and copies of it handed to detached tasks) share one cache.
final class UsageFileCache: @unchecked Sendable {
    struct Key: Equatable {
        var size: Int
        var mtime: Date
    }
    struct Entry {
        var key: Key
        var parsed: ClaudeUsageParser.Result
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var parsed = 0

    /// Total number of files actually decoded since creation (tests read this).
    var parseCount: Int { lock.withLock { parsed } }

    func entry(for path: String, key: Key) -> ClaudeUsageParser.Result? {
        lock.withLock {
            guard let e = entries[path], e.key == key else { return nil }
            return e.parsed
        }
    }

    func store(_ result: ClaudeUsageParser.Result, path: String, key: Key) {
        lock.withLock {
            entries[path] = Entry(key: key, parsed: result)
            parsed += 1
        }
    }

    /// Forget files that were not seen in the last pass (deleted or aged out of the window).
    func retain(paths: Set<String>) {
        lock.withLock { entries = entries.filter { paths.contains($0.key) } }
    }
}

/// Reads Claude Code session logs. The directory is injected; the default is the real one.
struct ClaudeUsageSource: UsageSource {
    var directory: URL
    let cache = UsageFileCache()

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.directory = directory
    }

    func load(modifiedSince: Date?) -> UsageLoadResult {
        var result = UsageLoadResult()
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return result }
        var all: [UsageRecord] = []
        var seen: Set<String> = []
        let parsedBefore = cache.parseCount
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? true else { continue }
            let mtime = values?.contentModificationDate
            if let since = modifiedSince, let mtime, mtime < since { continue }
            let path = url.path
            let key = UsageFileCache.Key(size: values?.fileSize ?? -1, mtime: mtime ?? .distantPast)
            let parsed: ClaudeUsageParser.Result
            if let hit = cache.entry(for: path, key: key) {
                parsed = hit
            } else {
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
                parsed = ClaudeUsageParser.parse(data: data)
                cache.store(parsed, path: path, key: key)
            }
            seen.insert(path)
            all.append(contentsOf: parsed.records)
            result.malformedLines += parsed.malformedLines
            result.fileCount += 1
        }
        cache.retain(paths: seen)
        result.parsedFileCount = cache.parseCount - parsedBefore
        // Dedupe runs on the merged cached + fresh records, so ids repeated across files stay correct.
        result.records = UsageRecord.deduplicated(all)
        return result
    }
}
