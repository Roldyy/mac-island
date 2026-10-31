import Darwin
import Foundation
import Testing
@testable import ClaudeLiveKit

/// Findings of the security audit: what a hostile or sloppy neighbour in the hook folder can do.
@Suite struct ClaudeHardeningTests {
    private func input(_ event: String, session: String = "abc-123") -> Data {
        Data("{\"hook_event_name\": \"\(event)\", \"session_id\": \"\(session)\", \"cwd\": \"/x/demo\"}".utf8)
    }

    private func names(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    private let foreignUID = getuid() &+ 1

    // MARK: SafeFileRead

    @Test func hardLinkedFileIsRefused() throws {
        let dir = TempDir()
        let original = dir.write("a.json", "{}")
        #expect(SafeFileRead.data(atPath: original.path, maxBytes: 100) != nil)
        let link = dir.url.appendingPathComponent("b.json").path
        #expect(Darwin.link(original.path, link) == 0)
        #expect(SafeFileRead.data(atPath: original.path, maxBytes: 100) == nil)
        #expect(SafeFileRead.data(atPath: link, maxBytes: 100) == nil)
    }

    @Test func fileOwnedBySomeoneElseIsRefused() {
        let dir = TempDir()
        let file = dir.write("a.json", "{}")
        #expect(SafeFileRead.data(atPath: file.path, maxBytes: 100) != nil)
        #expect(SafeFileRead.data(atPath: file.path, maxBytes: 100, uid: foreignUID) == nil)
    }

    @Test func drainingReadsTheWholeInputButKeepsOnlyTheCap() throws {
        let dir = TempDir()
        let size = ClaudeHookRunner.maxInputBytes * 3
        let file = dir.write("in.bin", String(repeating: "z", count: size))
        let fd = open(file.path, O_RDONLY)
        defer { close(fd) }
        let data = SafeFileRead.readCapped(fd: fd, limit: ClaudeHookRunner.maxInputBytes, rejectOverflow: false, drainRest: true)
        #expect(data?.count == ClaudeHookRunner.maxInputBytes)
        #expect(lseek(fd, 0, SEEK_CUR) == off_t(size), "stdin must be read to EOF")
    }

    // MARK: runner

    @Test func symlinkedHookFolderIsNeverWrittenOrDeletedIn() throws {
        let parent = TempDir()
        let real = parent.url.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let victim = real.appendingPathComponent("abc-123.json")
        try Data("{}".utf8).write(to: victim)
        let link = parent.url.appendingPathComponent("hooks")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        ClaudeHookRunner.run(input: input("Stop", session: "other"), directory: link)
        #expect(names(real) == ["abc-123.json"], "nothing may be written through the symlink")
        ClaudeHookRunner.run(input: input("SessionEnd"), directory: link)
        #expect(names(real) == ["abc-123.json"], "nothing may be deleted through the symlink")
        #expect(ClaudeHookStore(directory: link).read().isEmpty)
    }

    @Test func folderOwnedBySomeoneElseIsRefused() {
        let dir = TempDir()
        ClaudeHookRunner.run(input: input("Stop"), directory: dir.url, uid: foreignUID)
        #expect(names(dir.url).isEmpty)
        ClaudeHookRunner.run(input: input("Stop"), directory: dir.url)
        #expect(names(dir.url) == ["abc-123.json"])
        ClaudeHookRunner.run(input: input("SessionEnd"), directory: dir.url, uid: foreignUID)
        #expect(names(dir.url) == ["abc-123.json"])
        #expect(ClaudeHookStore(directory: dir.url, uid: foreignUID).read().isEmpty)
        #expect(ClaudeHookStore(directory: dir.url).read().count == 1)
    }

    @Test func plantedTempNameDoesNotBlockTheWrite() {
        let dir = TempDir()
        let planted = ".abc-123.\(getpid()).tmp"
        dir.write(planted, "planted")
        ClaudeHookRunner.run(input: input("Stop"), directory: dir.url)
        #expect(names(dir.url) == [planted, "abc-123.json"].sorted())
    }

    // MARK: store

    private func record(_ dir: TempDir, _ id: String, updatedAt: Double, state: String = "working") throws {
        let data = try JSONEncoder().encode(ClaudeHookRecord(state: state, folderName: "demo", updatedAt: updatedAt))
        dir.write("\(id).json", String(decoding: data, as: UTF8.self))
    }

    @Test func futureTimestampIsClampedToNow() throws {
        let dir = TempDir()
        try record(dir, "future", updatedAt: Fixture.now.timeIntervalSince1970 + 10_000_000)
        let read = ClaudeHookStore(directory: dir.url).read(now: Fixture.now)
        #expect(read["future"]?.updatedAt == Fixture.now.timeIntervalSince1970)

        // A real later change from the session file now wins instead of being pinned under the future value.
        let session = ClaudeSession(id: "future", pid: 1, state: .idle, folderName: "demo",
                                    updatedAt: Fixture.now.addingTimeInterval(1))
        #expect(ClaudeLiveSource.merge(sessions: [session], hooks: read).first?.state == .idle)
    }

    @Test func recordsOlderThanSevenDaysArePrunedWhenRead() throws {
        let dir = TempDir()
        let now = Fixture.now.timeIntervalSince1970
        try record(dir, "old", updatedAt: now - ClaudeHookStore.maxAge - 60)
        try record(dir, "fresh", updatedAt: now - ClaudeHookStore.maxAge + 3600)
        let read = ClaudeHookStore(directory: dir.url).read(now: Fixture.now)
        #expect(Array(read.keys) == ["fresh"])
        #expect(names(dir.url) == ["fresh.json"])
    }

    @Test func hardLinkedAndForeignRecordsAreSkippedByTheStore() throws {
        let dir = TempDir()
        try record(dir, "ok", updatedAt: Fixture.now.timeIntervalSince1970)
        try record(dir, "linked", updatedAt: Fixture.now.timeIntervalSince1970)
        #expect(Darwin.link(dir.url.appendingPathComponent("linked.json").path,
                            dir.url.appendingPathComponent("elsewhere.tmp").path) == 0)
        let read = ClaudeHookStore(directory: dir.url).read(now: Fixture.now)
        #expect(Array(read.keys) == ["ok"])
    }
}

private final class BundleAnchor {}

/// The hook runs on every Claude Code prompt and Claude Code reads its stdout: run the real binary.
@Suite struct ClaudeHookExecutableTests {
    /// SwiftPM puts executables next to the test bundle.
    private static func executable() -> URL? {
        var starts = [Bundle(for: BundleAnchor.self).bundleURL]
        // swift-testing runs inside `swiftpm-testing-helper`, which is told where the test bundle is.
        if let flag = CommandLine.arguments.firstIndex(of: "--test-bundle-path"), flag + 1 < CommandLine.arguments.count {
            starts.append(URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
        for start in starts {
            var dir = start.deletingLastPathComponent()
            for _ in 0..<5 {
                let candidate = dir.appendingPathComponent("ClaudeHook")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
                dir = dir.deletingLastPathComponent()
            }
        }
        return nil
    }

    private struct Outcome { var status: Int32; var stdout: Data; var stderr: Data }

    private func run(_ binary: URL, stdin: Data, hooks: URL) throws -> Outcome {
        let process = Process()
        process.executableURL = binary
        process.environment = ["MAC_ISLAND_HOOK_DIR": hooks.path]
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        // Writing past the pipe buffer needs the child to drain, so write from here and close.
        try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
        try? inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, stdout: out, stderr: err)
    }

    @Test func printsNothingAndExitsZeroForEveryEvent() throws {
        let binary = try #require(Self.executable(), "ClaudeHook was not built next to the tests")
        let hooks = TempDir()
        let events = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd", "PreToolUse"]
        for event in events {
            let json = Data("{\"hook_event_name\":\"\(event)\",\"session_id\":\"exec-1\",\"cwd\":\"/x/demo\",\"prompt\":\"never\"}".utf8)
            let outcome = try run(binary, stdin: json, hooks: hooks.url)
            #expect(outcome.status == 0, "\(event)")
            #expect(outcome.stdout.isEmpty, "\(event) wrote \(outcome.stdout.count) byte(s) on stdout")
        }
        // Last event was a harmless one: SessionEnd already removed the file the earlier events wrote.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: hooks.url.path)) ?? []).isEmpty)
    }

    @Test func writesTheRecordAndStaysSilent() throws {
        let binary = try #require(Self.executable(), "ClaudeHook was not built next to the tests")
        let hooks = TempDir()
        let json = Data("{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"exec-2\",\"cwd\":\"/x/demo\"}".utf8)
        let outcome = try run(binary, stdin: json, hooks: hooks.url)
        #expect(outcome.status == 0 && outcome.stdout.isEmpty)
        #expect(ClaudeHookStore(directory: hooks.url).read()["exec-2"]?.state == "working")
    }

    @Test func garbageAndHugeInputStillExitZeroSilently() throws {
        let binary = try #require(Self.executable(), "ClaudeHook was not built next to the tests")
        let hooks = TempDir()
        let inputs = [Data(), Data("not json".utf8), Data(repeating: 0x7B, count: ClaudeHookRunner.maxInputBytes * 8)]
        for data in inputs {
            let outcome = try run(binary, stdin: data, hooks: hooks.url)
            #expect(outcome.status == 0 && outcome.stdout.isEmpty)
        }
    }
}
