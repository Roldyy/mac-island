import Foundation

/// Reads Claude Code session logs. The directory is injected; the default is the real one.
struct ClaudeUsageSource: UsageSource {
    var directory: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.directory = directory
    }

    func load(modifiedSince: Date?) -> UsageLoadResult {
        var result = UsageLoadResult()
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return result }
        var all: [UsageRecord] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? true else { continue }
            if let since = modifiedSince, let mtime = values?.contentModificationDate, mtime < since { continue }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            let parsed = ClaudeUsageParser.parse(data: data)
            all.append(contentsOf: parsed.records)
            result.malformedLines += parsed.malformedLines
            result.fileCount += 1
        }
        result.records = UsageRecord.deduplicated(all)
        return result
    }
}
