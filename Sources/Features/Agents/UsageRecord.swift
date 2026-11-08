import Foundation

enum UsageAgent: String, Sendable, CaseIterable {
    case claude, codex

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

/// One assistant message worth of token usage. Never carries message content.
struct UsageRecord: Equatable, Sendable {
    var messageID: String?
    var model: String
    var timestamp: Date
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationTokens: Int
    var cacheReadTokens: Int
    /// Last path component of the working directory, never a full path. Empty when the log has none.
    var project: String = ""
    var agent: UsageAgent = .claude
    /// MIS_0120: who the request ran for, as Claude Code logs it (names only, all nil on a main-session request or
    /// an older log). Same fields its own /usage screen groups by.
    var attributionAgent: String?
    var attributionSkill: String?
    var attributionMcpServer: String?
    var attributionPlugin: String?
    /// First word of each Bash command the message called (git, gh, stb...). Never the command itself.
    var cliBinaries: [String] = []

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    /// Claude Code logs one line per streamed content block, repeating the message id with a growing
    /// `output_tokens`. Keep the entry with the largest output per id; records without an id are all kept.
    static func deduplicated(_ records: [UsageRecord]) -> [UsageRecord] {
        var best: [String: Int] = [:]
        var result: [UsageRecord] = []
        for record in records {
            guard let id = record.messageID else { result.append(record); continue }
            if let index = best[id] {
                // One line per content block repeats the id and the usage: every line's Bash calls count.
                let binaries = result[index].cliBinaries + record.cliBinaries
                if record.outputTokens > result[index].outputTokens { result[index] = record }
                result[index].cliBinaries = binaries
            } else {
                best[id] = result.count
                result.append(record)
            }
        }
        return result
    }
}

/// One run of a Claude Code hook, as the log records it. Names and numbers only: never the command, its output or a path.
struct HookRun: Equatable, Sendable {
    var name: String
    var event: String
    var durationMs: Int
    /// Exit code other than 0, or the hook was cancelled (timed out).
    var failed: Bool
    var timestamp: Date
    /// The log line's own id: the same run copied into a resumed session file is counted once.
    var uuid: String?
}

/// What a source hands back: records plus counts only (privacy rule: no content, no paths).
struct UsageLoadResult: Sendable {
    var records: [UsageRecord] = []
    var hooks: [HookRun] = []
    var malformedLines = 0
    var fileCount = 0
    /// Files actually decoded this pass (the rest came from the cache).
    var parsedFileCount = 0
    /// The source's folder does not exist (never used, or not installed).
    var directoryMissing = false
    /// Files that exist but could not be opened or read.
    var unreadableFiles = 0
}

/// A state of a load in flight: everything known so far, and how far the newest-first read has got.
struct UsageProgress: Sendable {
    var result: UsageLoadResult
    /// Newest modification date among files that have no data yet. A log never holds a record newer than its
    /// own mtime, so a period starting after this instant is complete. nil = every file has data.
    var missingNewest: Date?
    /// Newest modification date among files not read again yet, new or changed. A record of an open 5 h block
    /// can only sit in a file modified inside it, so the block is settled once this is older than 5 h.
    var pendingNewest: Date?
    /// This state is the disk cache alone: the folder has not been walked yet.
    var fromCache = false
}

protocol UsageSource: Sendable {
    /// `modifiedSince` lets a source skip files untouched since that date (nil = read everything).
    func load(modifiedSince: Date?) -> UsageLoadResult

    /// Same load, reporting intermediate states through `progress` (newest files first) and stopping early
    /// when `shouldContinue` turns false. The return value is the final state, never sent through `progress`.
    /// Called on the loading thread, never on the main actor.
    func load(modifiedSince: Date?, shouldContinue: () -> Bool, progress: (UsageProgress) -> Void) -> UsageLoadResult
}

extension UsageSource {
    /// A source that cannot report partial states just returns its end state.
    func load(modifiedSince: Date?, shouldContinue: () -> Bool, progress: (UsageProgress) -> Void) -> UsageLoadResult {
        load(modifiedSince: modifiedSince)
    }
}
