import Foundation

/// Reads Claude Code session logs. The directory is injected; the default is the real one.
///
/// A load first reports what the disk cache already knows (when one is configured), then walks the folder
/// and reads only the files that changed, newest first, reporting after every few of them. A file is read
/// from its last committed newline when it only grew, and whole otherwise.
struct ClaudeUsageSource: UsageSource {
    var directory: URL
    /// nil = memory cache only (tests, previews). The app passes `UsageCacheStore.default`.
    var store: UsageCacheStore?
    /// Files read at the same time. Bounded: each worker holds one 1 MB chunk plus its parsed records.
    var workers = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
    /// Minimum time between two progress reports (a report costs a merge and a snapshot build).
    var reportInterval: TimeInterval = 0.3
    let cache = UsageFileCache()

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
         store: UsageCacheStore? = nil) {
        self.directory = directory
        self.store = store
    }

    private struct FileInfo {
        var url: URL
        var path: String
        var key: UsageFileCache.Key
    }

    private struct ReadOutcome {
        var parse: ClaudeUsageParser.FileParse
        var fingerprint: Data
        var resumed: Bool
    }

    /// Fixed-size result slots filled from several threads, one index each.
    private final class Slots: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ReadOutcome?]
        init(count: Int) { items = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ value: ReadOutcome?) { lock.withLock { items[index] = value } }
        var all: [ReadOutcome?] { lock.withLock { items } }
    }

    private static func fingerprint(of url: URL, length: UInt64) -> Data? {
        let count = Int(min(length, UInt64(UsageFileCache.fingerprintBytes)))
        guard count > 0, let handle = try? FileHandle(forReadingFrom: url) else { return count == 0 ? Data() : nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }

    func load(modifiedSince: Date?) -> UsageLoadResult {
        load(modifiedSince: modifiedSince, shouldContinue: { true }, progress: { _ in })
    }

    func load(modifiedSince: Date?, shouldContinue: () -> Bool, progress: (UsageProgress) -> Void) -> UsageLoadResult {
        var result = UsageLoadResult()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            result.directoryMissing = true
            return result
        }
        // Warm start: the last known numbers go out before the folder is even walked.
        if let store, cache.restore(from: store) {
            let known = cache.merged()
            var early = UsageLoadResult()
            early.records = known.records
            early.malformedLines = known.malformed
            early.fileCount = known.files
            progress(UsageProgress(result: early, missingNewest: nil))
        }

        guard var files = scan(modifiedSince: modifiedSince, unreadable: &result.unreadableFiles) else { return result }
        files.sort { $0.key.mtime > $1.key.mtime }
        let todo = files.filter { cache.entry(for: $0.path)?.key != $0.key }
        // Files with nothing cached are the only ones whose period can still be incomplete.
        var missing = todo.filter { cache.entry(for: $0.path) == nil }.map(\.key.mtime)   // newest first

        let parsedBefore = cache.parseCount
        var unreadable: Set<String> = []
        var lastReport = Date()
        var lastSave = Date()
        var done = 0
        while done < todo.count, shouldContinue() {
            let batch = Array(todo[done..<min(done + workers, todo.count)])
            let slots = Slots(count: batch.count)
            if batch.count == 1 {
                slots.set(0, read(batch[0]))
            } else {
                DispatchQueue.concurrentPerform(iterations: batch.count) { slots.set($0, read(batch[$0])) }
            }
            for (info, outcome) in zip(batch, slots.all) {
                if let outcome {
                    cache.store(outcome.parse, path: info.path, key: info.key, fingerprint: outcome.fingerprint,
                                resumedRead: outcome.resumed)
                } else {
                    unreadable.insert(info.path)
                    result.unreadableFiles += 1
                }
            }
            done += batch.count
            // Read newest first, so what is still missing is whatever comes after `done` in `todo`.
            missing = todo[done...].filter { cache.entry(for: $0.path) == nil }.map(\.key.mtime)
            guard done < todo.count else { break }
            if Date().timeIntervalSince(lastReport) >= reportInterval {
                lastReport = Date()
                var partial = UsageLoadResult()
                let known = cache.merged()
                partial.records = known.records
                partial.malformedLines = known.malformed
                partial.fileCount = known.files
                partial.parsedFileCount = cache.parseCount - parsedBefore
                progress(UsageProgress(result: partial, missingNewest: missing.first))
            }
            if let store, Date().timeIntervalSince(lastSave) >= 3 {   // a cold read survives a quit half way
                lastSave = Date()
                store.write(cache.snapshot(), keepingSince: modifiedSince)
            }
        }

        let cancelled = done < todo.count
        var removed = 0
        if !cancelled {
            removed = cache.retain(paths: Set(files.map(\.path)).subtracting(unreadable))
        }
        let known = cache.merged()
        result.records = known.records
        result.malformedLines = known.malformed
        result.fileCount = known.files
        result.parsedFileCount = cache.parseCount - parsedBefore
        if let store, result.parsedFileCount > 0 || removed > 0 {
            store.write(cache.snapshot(), keepingSince: modifiedSince)
        }
        return result
    }

    /// Every `.jsonl` under the folder (links never followed) modified since the cutoff.
    private func scan(modifiedSince: Date?, unreadable: inout Int) -> [FileInfo]? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            unreadable += 1
            return nil
        }
        var files: [FileInfo] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {   // never follow a link out of the folder
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension == "jsonl", values?.isRegularFile ?? true else { continue }
            let mtime = values?.contentModificationDate
            if let since = modifiedSince, let mtime, mtime < since { continue }
            files.append(FileInfo(url: url, path: url.path,
                                  key: UsageFileCache.Key(size: values?.fileSize ?? -1, mtime: mtime ?? .distantPast)))
        }
        return files
    }

    /// Reads one changed file, resuming from the cached offset when it only grew. nil = unreadable.
    private func read(_ info: FileInfo) -> ReadOutcome? {
        var offset: UInt64 = 0
        var base = ClaudeUsageParser.FileParse()
        if let cached = cache.entry(for: info.path), info.key.size > cached.key.size, cached.parse.committedOffset > 0,
           Self.fingerprint(of: info.url, length: cached.parse.committedOffset) == cached.fingerprint {
            offset = cached.parse.committedOffset
            base = cached.parse
        }
        guard let fresh = try? ClaudeUsageParser.parse(file: info.url, from: offset) else { return nil }
        base.committed.append(fresh.committed)
        base.tail = fresh.tail
        base.committedOffset = fresh.committedOffset
        return ReadOutcome(parse: base,
                           fingerprint: Self.fingerprint(of: info.url, length: base.committedOffset) ?? Data(),
                           resumed: offset > 0)
    }
}
