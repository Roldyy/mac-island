import Foundation

/// One assistant message worth of token usage. Never carries message content.
struct UsageRecord: Equatable, Sendable {
    var messageID: String?
    var model: String
    var timestamp: Date
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    /// Claude Code logs one line per streamed content block, repeating the message id with a growing
    /// `output_tokens`. Keep the entry with the largest output per id; records without an id are all kept.
    static func deduplicated(_ records: [UsageRecord]) -> [UsageRecord] {
        var best: [String: Int] = [:]
        var result: [UsageRecord] = []
        for record in records {
            guard let id = record.messageID else { result.append(record); continue }
            if let index = best[id] {
                if record.outputTokens > result[index].outputTokens { result[index] = record }
            } else {
                best[id] = result.count
                result.append(record)
            }
        }
        return result
    }
}

/// What a source hands back: records plus counts only (privacy rule: no content, no paths).
struct UsageLoadResult: Sendable {
    var records: [UsageRecord] = []
    var malformedLines = 0
    var fileCount = 0
    /// Files actually decoded this pass (the rest came from the cache).
    var parsedFileCount = 0
}

protocol UsageSource: Sendable {
    /// `modifiedSince` lets a source skip files untouched since that date (nil = read everything).
    func load(modifiedSince: Date?) -> UsageLoadResult
}
