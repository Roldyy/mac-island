import Foundation
import Testing
@testable import AgentsFeature

@Suite struct UsageParsingTests {
    static func line(id: String?, model: String = "claude-sonnet-5-5", ts: String = "2026-10-05T10:00:00.000Z",
                     input: Int = 10, output: Int = 20, cw: Int = 30, cr: Int = 40) -> String {
        let idPart = id.map { "\"id\":\"\($0)\"," } ?? ""
        return """
        {"type":"assistant","timestamp":"\(ts)","extra":{"a":1},"message":{\(idPart)"model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cw),"cache_read_input_tokens":\(cr),"service_tier":"standard"}}}
        """
    }

    @Test func parsesAssistantUsage() {
        let r = ClaudeUsageParser.parse(lines: [Self.line(id: "m1")])
        #expect(r.records.count == 1)
        #expect(r.malformedLines == 0)
        let rec = r.records[0]
        #expect(rec.model == "claude-sonnet-5-5")
        #expect(rec.inputTokens == 10 && rec.outputTokens == 20)
        #expect(rec.cacheCreationTokens == 30 && rec.cacheReadTokens == 40)
        #expect(rec.totalTokens == 100)
    }

    @Test func skipsNonUsageLinesAndCountsMalformed() {
        let r = ClaudeUsageParser.parse(lines: [
            "{\"type\":\"user\",\"message\":{\"role\":\"user\"}}",
            "{not json",
            "",
            Self.line(id: "m1"),
        ])
        #expect(r.records.count == 1)
        #expect(r.malformedLines == 1)
    }

    @Test func parsesTimestampWithAndWithoutFraction() {
        let a = ClaudeUsageParser.parse(lines: [Self.line(id: "a", ts: "2026-10-05T10:00:00.123Z")])
        let b = ClaudeUsageParser.parse(lines: [Self.line(id: "b", ts: "2026-10-05T10:00:00Z")])
        #expect(a.records.count == 1 && b.records.count == 1)
    }

    @Test func missingTimestampCountsAsMalformed() {
        let l = "{\"type\":\"assistant\",\"message\":{\"model\":\"m\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}"
        let r = ClaudeUsageParser.parse(lines: [l])
        #expect(r.records.isEmpty)
        #expect(r.malformedLines == 1)
    }

    @Test func dedupeKeepsLargestOutputPerMessageId() {
        let r = ClaudeUsageParser.parse(lines: [
            Self.line(id: "m1", output: 5),
            Self.line(id: "m1", output: 50),
            Self.line(id: "m1", output: 7),
            Self.line(id: "m2", output: 1),
            Self.line(id: nil, output: 3),
            Self.line(id: nil, output: 3),
        ])
        let d = UsageRecord.deduplicated(r.records)
        #expect(d.count == 4)
        #expect(d.first { $0.messageID == "m1" }?.outputTokens == 50)
    }

    @Test func sourceReadsDirectoryRecursivelyAndDedupesAcrossFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agents-test-\(UUID().uuidString)")
        let sub = dir.appendingPathComponent("p1")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try [Self.line(id: "m1", output: 5), "garbage"].joined(separator: "\n")
            .write(to: sub.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try [Self.line(id: "m1", output: 9), Self.line(id: "m2")].joined(separator: "\n")
            .write(to: dir.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)
        try "ignored".write(to: dir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

        let result = ClaudeUsageSource(directory: dir).load(modifiedSince: nil)
        #expect(result.fileCount == 2)
        #expect(result.malformedLines == 1)
        #expect(result.records.count == 2)
        #expect(result.records.first { $0.messageID == "m1" }?.outputTokens == 9)
    }

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agents-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func secondPassOverUnchangedFilesParsesNothing() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.line(id: "m1").write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try Self.line(id: "m2").write(to: dir.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)
        let source = ClaudeUsageSource(directory: dir)
        let first = source.load(modifiedSince: nil)
        #expect(first.parsedFileCount == 2)
        let second = source.load(modifiedSince: nil)
        #expect(second.parsedFileCount == 0)
        #expect(source.cache.parseCount == 2)
        #expect(second.fileCount == 2)
        #expect(second.records == first.records)
    }

    @Test func modifiedFileIsReparsedAndDedupeHoldsAcrossCachedAndFresh() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.jsonl"), b = dir.appendingPathComponent("b.jsonl")
        try Self.line(id: "m1", output: 5).write(to: a, atomically: true, encoding: .utf8)
        try Self.line(id: "m2", output: 1).write(to: b, atomically: true, encoding: .utf8)
        let source = ClaudeUsageSource(directory: dir)
        _ = source.load(modifiedSince: nil)
        // b grows a bigger copy of m1 (cached a.jsonl must still merge with fresh b.jsonl).
        try [Self.line(id: "m2", output: 1), Self.line(id: "m1", output: 99)].joined(separator: "\n")
            .write(to: b, atomically: true, encoding: .utf8)
        let r = source.load(modifiedSince: nil)
        #expect(r.parsedFileCount == 1)
        #expect(r.records.count == 2)
        #expect(r.records.first { $0.messageID == "m1" }?.outputTokens == 99)
    }

    @Test func modifiedSinceSkipsOldFiles() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("old.jsonl"), fresh = dir.appendingPathComponent("new.jsonl")
        try Self.line(id: "old").write(to: old, atomically: true, encoding: .utf8)
        try Self.line(id: "new").write(to: fresh, atomically: true, encoding: .utf8)
        let longAgo = Date(timeIntervalSinceNow: -90 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)
        let r = ClaudeUsageSource(directory: dir).load(modifiedSince: Date(timeIntervalSinceNow: -86_400))
        #expect(r.fileCount == 1)
        #expect(r.records.map(\.messageID) == ["new"])
    }

    @Test func missingDirectoryYieldsEmpty() {
        let r = ClaudeUsageSource(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")).load(modifiedSince: nil)
        #expect(r.records.isEmpty && r.fileCount == 0)
    }

    @Test func codexStubReturnsNoData() {
        #expect(CodexUsageSource().load(modifiedSince: nil).records.isEmpty)
    }
}
