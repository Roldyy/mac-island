import Foundation
import Testing
@testable import AgentsFeature

/// Synthetic logs only: never real content.
@Suite struct StreamingTests {
    static func line(_ id: String, cwd: String = "/Users/someone/work/demo", o: Int = 5,
                     ts: String = "2026-10-05T10:00:00.000Z") -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","cwd":"\(cwd)","message":{"id":"\(id)","model":"claude-sonnet-5-5","usage":{"input_tokens":1,"output_tokens":\(o),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agents-stream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func projectIsTheLastPathComponentOnly() {
        let r = ClaudeUsageParser.parse(lines: [Self.line("a", cwd: "/Users/someone/work/demo")])
        #expect(r.records.first?.project == "demo")
    }

    @Test func streamHandlesLinesAcrossChunkBoundariesAndLongLines() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // ~3.5 MB with one 1.5 MB filler line (no usage) straddling chunk boundaries.
        let filler = "{\"type\":\"user\",\"pad\":\"" + String(repeating: "x", count: 1_500_000) + "\"}"
        let lines = (0..<10).map { Self.line("m\($0)") } + [filler] + (10..<20).map { Self.line("m\($0)") }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let parsed = try ClaudeUsageParser.parse(file: dir.appendingPathComponent("a.jsonl"))
        #expect(parsed.committed.records.count + parsed.tail.records.count == 20)
        #expect(parsed.committed.malformedLines == 0)
    }

    @Test func malformedLinesAreCountedNotFatal() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = [Self.line("a"), "{broken", "\u{1}\u{2}garbage", Self.line("b")].joined(separator: "\n") + "\n"
        try body.write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let parsed = try ClaudeUsageParser.parse(file: dir.appendingPathComponent("a.jsonl"))
        #expect(parsed.committed.records.count == 2)
        #expect(parsed.committed.malformedLines == 2)
    }

    @Test func partialTailIsNotCommitted() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = Self.line("a") + "\n"
        try (first + String(Self.line("b").prefix(40))).write(to: dir.appendingPathComponent("a.jsonl"),
                                                              atomically: true, encoding: .utf8)
        let parsed = try ClaudeUsageParser.parse(file: dir.appendingPathComponent("a.jsonl"))
        #expect(parsed.committed.records.count == 1)
        #expect(parsed.tail.records.isEmpty)
        #expect(parsed.committedOffset == UInt64(first.utf8.count))
    }

    @Test func growingFileIsResumedNotReread() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.jsonl")
        try (Self.line("m1") + "\n").write(to: url, atomically: true, encoding: .utf8)
        let source = ClaudeUsageSource(directory: dir)
        #expect(source.load(modifiedSince: nil).records.count == 1)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Self.line("m2") + "\n").utf8))
        try handle.close()
        // Same mtime second is possible: force a different one so the key changes.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: url.path)
        let second = source.load(modifiedSince: nil)
        #expect(second.records.map(\.messageID) == ["m1", "m2"])
        #expect(second.parsedFileCount == 1)
        #expect(source.cache.resumeCount == 1)
    }

    @Test func rewrittenFileWithDifferentStartIsReadAgain() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.jsonl")
        try (Self.line("old") + "\n").write(to: url, atomically: true, encoding: .utf8)
        let source = ClaudeUsageSource(directory: dir)
        _ = source.load(modifiedSince: nil)
        try (Self.line("new1", o: 1) + "\n" + Self.line("new2") + "\n" + Self.line("new3") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: url.path)
        let r = source.load(modifiedSince: nil)
        #expect(Set(r.records.compactMap(\.messageID)) == ["new1", "new2", "new3"])
        #expect(source.cache.resumeCount == 0)
    }

    @Test func symlinkedFilesAndFoldersAreSkipped() throws {
        let dir = try makeDir()
        let outside = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: outside) }
        try (Self.line("real") + "\n").write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try (Self.line("elsewhere") + "\n").write(to: outside.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link.jsonl"),
                                                   withDestinationURL: outside.appendingPathComponent("b.jsonl"))
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("linked-dir"), withDestinationURL: outside)
        let r = ClaudeUsageSource(directory: dir).load(modifiedSince: nil)
        #expect(r.records.map(\.messageID) == ["real"])
    }

    @Test func missingDirectoryIsReportedAsMissing() {
        let r = ClaudeUsageSource(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")).load(modifiedSince: nil)
        #expect(r.directoryMissing)
        #expect(CodexUsageSource(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
            .load(modifiedSince: nil).directoryMissing)
    }

    @Test func unreadableFileIsCountedAndSkipped() throws {
        let dir = try makeDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dir.appendingPathComponent("bad.jsonl").path)
            try? FileManager.default.removeItem(at: dir)
        }
        try (Self.line("ok") + "\n").write(to: dir.appendingPathComponent("ok.jsonl"), atomically: true, encoding: .utf8)
        try (Self.line("bad") + "\n").write(to: dir.appendingPathComponent("bad.jsonl"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.appendingPathComponent("bad.jsonl").path)
        let r = ClaudeUsageSource(directory: dir).load(modifiedSince: nil)
        #expect(r.records.map(\.messageID) == ["ok"])
        #expect(r.unreadableFiles == 1)
    }

    @Test func liveSessionLabelsAndOrder() {
        #expect(AgentsLiveModel.label(for: .working) == "travaille")
        #expect(AgentsLiveModel.label(for: .waiting) == "attend")
        #expect(AgentsLiveModel.label(for: .idle) == "inactif")
    }
}
