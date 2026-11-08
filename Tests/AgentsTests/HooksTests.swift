import Foundation
import Testing
@testable import AgentsFeature

/// MIS_0120: hooks spend no tokens, so the card shows runs, time and errors per hook, never a share.
struct HooksTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!

    static let lines = [
        #"{"type":"attachment","timestamp":"2026-11-08T10:20:00.000Z","uuid":"u1","attachment":{"type":"hook_success","hookName":"PostToolUse:Edit","hookEvent":"PostToolUse","exitCode":0,"durationMs":120,"command":"/secret/path/run.sh","stdout":"private text","stderr":""}}"#,
        #"{"type":"attachment","timestamp":"2026-11-08T10:21:00.000Z","uuid":"u2","attachment":{"type":"hook_success","hookName":"PostToolUse:Edit","hookEvent":"PostToolUse","exitCode":1,"durationMs":80,"command":"/secret/path/run.sh","stdout":"","stderr":"boom"}}"#,
        #"{"type":"attachment","timestamp":"2026-11-08T10:22:00.000Z","uuid":"u3","attachment":{"type":"hook_cancelled","hookName":"PreToolUse:Bash","hookEvent":"PreToolUse","timedOut":true,"timeoutMs":5000}}"#,
        #"{"type":"attachment","timestamp":"2026-11-08T10:23:00.000Z","uuid":"u4","attachment":{"type":"hook_additional_context","hookName":"SessionStart:startup","hookEvent":"SessionStart","content":"context text"}}"#,
        #"{"type":"attachment","timestamp":"2026-10-01T10:00:00.000Z","uuid":"u5","attachment":{"type":"hook_success","hookName":"Old:Hook","hookEvent":"Old","exitCode":0,"durationMs":5}}"#,
    ]

    @Test func parserKeepsRunsDurationsAndFailuresAndNothingElse() {
        let result = ClaudeUsageParser.parse(lines: Self.lines)
        #expect(result.malformedLines == 0)
        #expect(result.records.isEmpty)
        // success + success + cancelled + the old one; the additional-context line is not a run.
        #expect(result.hooks.count == 4)
        let byID = Dictionary(uniqueKeysWithValues: result.hooks.map { ($0.uuid ?? "", $0) })
        #expect(byID["u1"]?.name == "PostToolUse:Edit")
        #expect(byID["u1"]?.durationMs == 120)
        #expect(byID["u1"]?.failed == false)
        #expect(byID["u2"]?.failed == true)          // exit code 1
        #expect(byID["u3"]?.failed == true)          // cancelled
        // A timed-out hook counts the time it was allowed, not an outlier wait.
        #expect(byID["u3"]?.durationMs == 5000)
    }

    @Test func hooksAreCountedPerNameInTheWindow() {
        let hooks = ClaudeUsageParser.parse(lines: Self.lines).hooks
        let b = UsageBreakdown.build([], hooks: hooks, now: Self.now, window: .days7)
        #expect(b.hooks.map(\.name) == ["PostToolUse:Edit", "PreToolUse:Bash"])
        let edit = b.hooks[0]
        #expect(edit.runs == 2 && edit.totalMs == 200 && edit.errors == 1)
        #expect(b.hooks[1].runs == 1 && b.hooks[1].errors == 1 && b.hooks[1].totalMs == 5000)
        // The 38-day-old run is outside 30 days too.
        #expect(UsageBreakdown.build([], hooks: hooks, now: Self.now, window: .days30).hooks.count == 2)
        #expect(!b.isEmpty || b.totalWeight == 0)
    }

    @Test func aHooksOnlyWindowIsNotEmptyForTheCard() {
        let hooks = ClaudeUsageParser.parse(lines: Self.lines).hooks
        #expect(!UsageBreakdown.build([], hooks: hooks, now: Self.now, window: .days7).isEmpty)
        #expect(UsageBreakdown.build([], hooks: [], now: Self.now, window: .days7).isEmpty)
    }

    @Test func hooksSurviveTheDiskCacheAndAreDeduplicatedAcrossFiles() throws {
        var parse = ClaudeUsageParser.FileParse()
        parse.committed = ClaudeUsageParser.parse(lines: Self.lines)
        let entry = UsageFileCache.Entry(key: .init(size: 10, mtime: Self.now), parse: parse, fingerprint: Data([1]))
        let decoded = try UsageCacheCodec.decode(UsageCacheCodec.encode(["/a.jsonl": entry]))
        #expect(decoded["/a.jsonl"]?.parse.committed.hooks == parse.committed.hooks)

        let cache = UsageFileCache()
        cache.store(parse, path: "/old.jsonl", key: .init(size: 1, mtime: Self.now), fingerprint: Data())
        cache.store(parse, path: "/resumed.jsonl", key: .init(size: 1, mtime: Self.now), fingerprint: Data())
        #expect(cache.merged().hooks.count == 4)   // the resumed copy is not counted twice
    }
}
