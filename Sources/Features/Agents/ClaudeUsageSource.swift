import Foundation

/// Per-file parse cache keyed by path + size + mtime. A reference type so the value-type source
/// (and copies of it handed to detached tasks) share one cache. Logs only grow, so a bigger file whose
/// first bytes are unchanged is resumed from the last committed newline instead of re-read.
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

    /// Total number of file reads (full or resumed) since creation (tests read this).
    var parseCount: Int { lock.withLock { parsed } }

    /// Reads that resumed from a cached offset instead of starting over.
    var resumeCount: Int { lock.withLock { resumed } }

    func entry(for path: String) -> Entry? { lock.withLock { entries[path] } }

    func store(_ parse: ClaudeUsageParser.FileParse, path: String, key: Key, fingerprint: Data, resumedRead: Bool = false) {
        lock.withLock {
            if resumedRead { resumed += 1 }
            entries[path] = Entry(key: key, parse: parse, fingerprint: fingerprint)
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

    private static func fingerprint(of url: URL, length: UInt64) -> Data? {
        let count = Int(min(length, UInt64(UsageFileCache.fingerprintBytes)))
        guard count > 0, let handle = try? FileHandle(forReadingFrom: url) else { return count == 0 ? Data() : nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }

    func load(modifiedSince: Date?) -> UsageLoadResult {
        var result = UsageLoadResult()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            result.directoryMissing = true
            return result
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            result.unreadableFiles += 1
            return result
        }
        var all: [UsageRecord] = []
        var seen: Set<String> = []
        let parsedBefore = cache.parseCount
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {   // never follow a link out of the folder
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension == "jsonl", values?.isRegularFile ?? true else { continue }
            let mtime = values?.contentModificationDate
            if let since = modifiedSince, let mtime, mtime < since { continue }
            let path = url.path
            let size = values?.fileSize ?? -1
            let key = UsageFileCache.Key(size: size, mtime: mtime ?? .distantPast)
            let cached = cache.entry(for: path)
            let parse: ClaudeUsageParser.FileParse
            if let cached, cached.key == key {
                parse = cached.parse
            } else {
                var offset: UInt64 = 0
                var base = ClaudeUsageParser.FileParse()
                if let cached, size > cached.key.size, cached.parse.committedOffset > 0,
                   Self.fingerprint(of: url, length: cached.parse.committedOffset) == cached.fingerprint {
                    offset = cached.parse.committedOffset
                    base = cached.parse
                }
                guard let fresh = try? ClaudeUsageParser.parse(file: url, from: offset) else {
                    result.unreadableFiles += 1
                    continue
                }
                base.committed.append(fresh.committed)
                base.tail = fresh.tail
                base.committedOffset = fresh.committedOffset
                parse = base
                cache.store(parse, path: path, key: key,
                            fingerprint: Self.fingerprint(of: url, length: parse.committedOffset) ?? Data(),
                            resumedRead: offset > 0)
            }
            seen.insert(path)
            all.append(contentsOf: parse.committed.records)
            all.append(contentsOf: parse.tail.records)
            result.malformedLines += parse.committed.malformedLines + parse.tail.malformedLines
            result.fileCount += 1
        }
        cache.retain(paths: seen)
        result.parsedFileCount = cache.parseCount - parsedBefore
        // Dedupe runs on the merged cached + fresh records, so ids repeated across files stay correct.
        result.records = UsageRecord.deduplicated(all)
        return result
    }
}
