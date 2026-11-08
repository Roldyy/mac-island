import Foundation
import Testing
@testable import AgentsFeature

/// MIS_0120: the "what contributes to my usage" card. Weights follow Claude Code's own /usage screen:
/// (cache_read + input*10 + cache_creation*12.5 + output*50) * tier (haiku 1, other 3, opus 5, fable 10).
struct BreakdownTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!

    /// main opus (+ a Bash call), subagent Explore on haiku, MCP stb on sonnet, an old line with no attribution,
    /// and one 19 days old (outside 7 days, inside 30).
    static let lines = [
        #"{"type":"assistant","timestamp":"2026-11-08T10:00:00.000Z","cwd":"/x/proj","message":{"id":"m1","model":"claude-opus-4-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":4,"cache_read_input_tokens":100},"content":[{"type":"text","text":"hi"},{"type":"tool_use","name":"Bash","input":{"command":"cd /tmp && git status"}}]}}"#,
        #"{"type":"assistant","timestamp":"2026-11-08T10:05:00.000Z","cwd":"/x/proj","isSidechain":true,"attributionAgent":"Explore","message":{"id":"m2","model":"claude-haiku-4-5","usage":{"input_tokens":5,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":40},"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a"}}]}}"#,
        #"{"type":"assistant","timestamp":"2026-11-08T10:10:00.000Z","cwd":"/x/proj","attributionMcpServer":"stb","message":{"id":"m3","model":"claude-sonnet-4-5","usage":{"input_tokens":2,"output_tokens":4,"cache_creation_input_tokens":8,"cache_read_input_tokens":20},"content":[{"type":"tool_use","name":"mcp__stb__odoo_search_read","input":{}}]}}"#,
        #"{"type":"assistant","timestamp":"2026-11-08T10:15:00.000Z","cwd":"/x/proj","message":{"id":"m4","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":2},"content":"plain string content"}}"#,
        #"{"type":"assistant","timestamp":"2026-10-20T10:00:00.000Z","cwd":"/x/proj","message":{"id":"m5","model":"claude-opus-4-5","usage":{"input_tokens":1,"output_tokens":0}}}"#,
    ]

    static var records: [UsageRecord] { ClaudeUsageParser.parse(lines: lines).records }

    @Test func parserReadsAttributionAndBashBinariesAndSurvivesStringContent() {
        let result = ClaudeUsageParser.parse(lines: Self.lines)
        #expect(result.malformedLines == 0)
        #expect(result.records.count == 5)
        let byID = Dictionary(uniqueKeysWithValues: result.records.map { ($0.messageID ?? "", $0) })
        #expect(byID["m1"]?.cliBinaries == ["git"])
        #expect(byID["m2"]?.attributionAgent == "Explore")
        #expect(byID["m2"]?.cliBinaries == [])
        #expect(byID["m3"]?.attributionMcpServer == "stb")
        #expect(byID["m4"]?.attributionAgent == nil)
    }

    @Test func bashBinaryIsTheCommandNotTheWrapper() {
        #expect(ClaudeUsageParser.bashBinary("git status") == "git")
        #expect(ClaudeUsageParser.bashBinary("cd /tmp && gh pr list") == "gh")
        #expect(ClaudeUsageParser.bashBinary("FOO=1 BAR=2 swift test --filter X") == "swift")
        #expect(ClaudeUsageParser.bashBinary("sudo -n ls") == "ls")
        #expect(ClaudeUsageParser.bashBinary("/usr/bin/python3 x.py") == "python3")
        #expect(ClaudeUsageParser.bashBinary("   ") == nil)
    }

    @Test func quotedPathsKeywordsAndBuiltinsDoNotPoseAsCommands() {
        // A path with a blank is one word, not two.
        #expect(ClaudeUsageParser.bashBinary("cd \"/Users/x/GOOGLE DRIVE/code\" && git log") == "git")
        #expect(ClaudeUsageParser.bashBinary("cd '/a b'; ls -la") == "ls")
        #expect(ClaudeUsageParser.bashBinary("builtin cd \"/a b/c\" && swift build") == "swift")
        // Loops and conditions: the command after `do` / `then`.
        #expect(ClaudeUsageParser.bashBinary("for f in *.swift; do wc -l $f; done") == "wc")
        #expect(ClaudeUsageParser.bashBinary("until [ -f x ]; do sleep 2; done") == "sleep")
        #expect(ClaudeUsageParser.bashBinary("if [ -d x ]; then ls x; fi") == "ls")
        #expect(ClaudeUsageParser.bashBinary("for f in a b") == nil)
        // Never a leftover quote or semicolon.
        #expect(ClaudeUsageParser.bashBinary("echo hi;") == "echo")
        #expect(ClaudeUsageParser.bashBinary("(cd /tmp && ls)") == "ls")
    }

    @Test func weightsMatchTheUsageScreenFormula() {
        let b = UsageBreakdown.build(Self.records, now: Self.now, window: .days7)
        #expect(b.totalWeight == 8190)
        let rows = Dictionary(uniqueKeysWithValues: b.subagents.map { ($0.name, $0) })
        #expect(rows["Explore"]?.weight == 590)
        #expect(rows[UsageBreakdown.mainSession]?.weight == 7600)
        #expect(b.mcpServers.first?.name == "stb")
        #expect(b.mcpServers.first?.weight == 1020)
    }

    @Test func categoryWeightsAddUpToTheTotalToTheToken() {
        let b = UsageBreakdown.build(Self.records, now: Self.now, window: .days7)
        #expect(b.subagents.reduce(0) { $0 + $1.weight } == b.totalWeight)
    }

    @Test func eachRowCarriesItsModelMix() {
        let b = UsageBreakdown.build(Self.records, now: Self.now, window: .days7)
        let main = b.subagents.first { $0.name == UsageBreakdown.mainSession }!
        // main: opus 6250 of 7600, sonnet (m3 1020 + m4 330) 1350 of 7600.
        let opus = main.models.first { $0.family == .opus }!.share
        let sonnet = main.models.first { $0.family == .sonnet }!.share
        #expect(abs(opus - 6250.0 / 7600.0) < 1e-9)
        #expect(abs(sonnet - 1350.0 / 7600.0) < 1e-9)
        #expect(abs(main.models.reduce(0) { $0 + $1.share } - 1) < 1e-9)
    }

    @Test func windowsFollowTheLineTimestampNotTheFile() {
        #expect(UsageBreakdown.build(Self.records, now: Self.now, window: .hours24).totalWeight == 8190)
        #expect(UsageBreakdown.build(Self.records, now: Self.now, window: .days7).totalWeight == 8190)
        #expect(UsageBreakdown.build(Self.records, now: Self.now, window: .days30).totalWeight == 8240)
    }

    @Test func cliBinariesAreCountedByCall() {
        let b = UsageBreakdown.build(Self.records, now: Self.now, window: .days7)
        #expect(b.cli.map(\.name) == ["git"])
        #expect(b.cli.first?.calls == 1)
    }

    @Test func attributionAndBinariesSurviveTheDiskCache() throws {
        var parse = ClaudeUsageParser.FileParse()
        parse.committed.records = Self.records
        let entry = UsageFileCache.Entry(key: .init(size: 10, mtime: Self.now), parse: parse, fingerprint: Data([1]))
        let decoded = try UsageCacheCodec.decode(UsageCacheCodec.encode(["/a.jsonl": entry]))
        #expect(decoded["/a.jsonl"]?.parse.committed.records == Self.records)
        #expect(UsageBreakdown.build(decoded["/a.jsonl"]!.parse.committed.records, now: Self.now, window: .days7)
                == UsageBreakdown.build(Self.records, now: Self.now, window: .days7))
    }

    // MARK: review fixes (Opus review of MIS_0120)

    /// Claude Code writes one line per content block, each repeating the message id and the usage: the Bash call
    /// is usually on a later line than the text or thinking block.
    @Test func aBashCallOnALaterLineOfTheSameMessageIsCounted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let usage = #""usage":{"input_tokens":3,"output_tokens":120,"cache_creation_input_tokens":0,"cache_read_input_tokens":10}"#
        let a = #"{"type":"assistant","timestamp":"2026-11-08T10:00:00.000Z","message":{"id":"m1","model":"claude-opus-4-5",\#(usage),"content":[{"type":"text","text":"x"}]}}"#
        let b = #"{"type":"assistant","timestamp":"2026-11-08T10:00:01.000Z","message":{"id":"m1","model":"claude-opus-4-5",\#(usage),"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}"#
        let c = #"{"type":"assistant","timestamp":"2026-11-08T10:00:02.000Z","message":{"id":"m1","model":"claude-opus-4-5",\#(usage),"content":[{"type":"tool_use","name":"Bash","input":{"command":"gh pr list"}}]}}"#
        let file = dir.appendingPathComponent("s.jsonl")
        try ([a, b, c].joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        let parsed = try ClaudeUsageParser.parse(file: file)
        #expect(parsed.committed.records.count == 1)
        #expect(parsed.committed.records.first?.cliBinaries == ["git", "gh"])
    }

    @Test func deduplicatedKeepsTheBinariesOfEveryLineOfOneMessage() {
        func record(_ id: String, _ binaries: [String], output: Int) -> UsageRecord {
            UsageRecord(messageID: id, model: "m", timestamp: Self.now, inputTokens: 1, outputTokens: output,
                        cacheCreationTokens: 0, cacheReadTokens: 0, cliBinaries: binaries)
        }
        let merged = UsageRecord.deduplicated([record("a", ["git"], output: 5), record("a", ["gh"], output: 5),
                                               record("b", ["ls"], output: 1)])
        #expect(merged.count == 2)
        #expect(merged.first { $0.messageID == "a" }?.cliBinaries == ["git", "gh"])
    }

    @Test func aMessageCopiedIntoAResumedFileIsCountedOnceAcrossFiles() {
        func entry(_ binaries: [String]) -> UsageFileCache.Entry {
            var parse = ClaudeUsageParser.FileParse()
            parse.committed.records = [UsageRecord(messageID: "a", model: "m", timestamp: Self.now, inputTokens: 1,
                                                   outputTokens: 5, cacheCreationTokens: 0, cacheReadTokens: 0,
                                                   cliBinaries: binaries)]
            return .init(key: .init(size: 1, mtime: Self.now), parse: parse, fingerprint: Data())
        }
        let cache = UsageFileCache()
        cache.store(entry(["git", "gh"]).parse, path: "/old.jsonl", key: .init(size: 1, mtime: Self.now), fingerprint: Data())
        cache.store(entry(["git", "gh"]).parse, path: "/resumed.jsonl", key: .init(size: 1, mtime: Self.now), fingerprint: Data())
        #expect(cache.merged().records.count == 1)
        #expect(cache.merged().records.first?.cliBinaries == ["git", "gh"])   // not doubled
    }

    @Test func anOddAttributionValueNeverMakesTheLineMalformed() {
        let line = #"{"type":"assistant","timestamp":"2026-11-08T10:00:00.000Z","attributionPlugin":{"name":"x"},"attributionAgent":7,"message":{"id":"m9","model":"claude-opus-4-5","usage":{"input_tokens":1,"output_tokens":2}}}"#
        let result = ClaudeUsageParser.parse(lines: [line])
        #expect(result.malformedLines == 0)
        #expect(result.records.count == 1)
        #expect(result.records.first?.attributionPlugin == nil)
        #expect(result.records.first?.attributionAgent == nil)
    }

    @Test func aBinaryNameIsAWordNeverAPieceOfTheCommand() {
        #expect(ClaudeUsageParser.bashBinary("\"my tool\" --x") == nil)
        #expect(ClaudeUsageParser.bashBinary("run\\ me.sh") == nil)
        #expect(ClaudeUsageParser.bashBinary("${HOME}/bin/x") == nil)
        #expect(ClaudeUsageParser.bashBinary("python3.12 x.py") == "python3.12")
        #expect(ClaudeUsageParser.bashBinary("g++ main.cc") == "g++")
    }

    @Test func emptyInputGivesEmptyRowsAndNoDivisionByZero() {
        let b = UsageBreakdown.build([], now: Self.now, window: .days7)
        #expect(b.totalWeight == 0)
        #expect(b.subagents.isEmpty && b.mcpServers.isEmpty && b.cli.isEmpty)
    }
}
