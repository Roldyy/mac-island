import Darwin
import Foundation
import Testing
@testable import ClaudeLiveKit

@Suite struct ClaudeHookTests {
    private func input(_ event: String, session: String = "abc-123", cwd: String? = "/Users/someone/work/demo",
                       extra: String = "") -> Data {
        var parts = ["\"hook_event_name\": \"\(event)\"", "\"session_id\": \"\(session)\""]
        if let cwd { parts.append("\"cwd\": \"\(cwd)\"") }
        if !extra.isEmpty { parts.append(extra) }
        return Data("{\(parts.joined(separator: ","))}".utf8)
    }

    private func files(_ dir: TempDir) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.url.path)) ?? []).sorted()
    }

    @Test func eventsMapToStates() {
        let now = Fixture.now
        func state(_ e: String) -> String? {
            if case .write(_, let r) = ClaudeHookRunner.decide(input: input(e), now: now) { r.state } else { nil }
        }
        #expect(state("SessionStart") == "idle")
        #expect(state("UserPromptSubmit") == "working")
        #expect(state("Notification") == "waiting")
        #expect(state("Stop") == "idle")
        #expect(state("PreToolUse") == nil)
        #expect(ClaudeHookRunner.decide(input: input("SessionEnd"), now: now) == .delete(id: "abc-123"))
    }

    @Test func recordHoldsOnlyStateFolderAndTime() throws {
        let dir = TempDir()
        let payload = input("UserPromptSubmit",
                            extra: "\"prompt\": \"SECRET-PROMPT-TEXT\", \"transcript_path\": \"/private/x\"")
        let out = ClaudeHookRunner.run(input: payload, directory: dir.url, now: Fixture.now)
        #expect(out.isEmpty)
        #expect(files(dir) == ["abc-123.json"])
        let text = try String(contentsOf: dir.url.appendingPathComponent("abc-123.json"), encoding: .utf8)
        #expect(!text.contains("SECRET-PROMPT-TEXT"))
        #expect(!text.contains("/private/x"))
        #expect(!text.contains("someone"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["state", "folderName", "updatedAt"])
        #expect(object["folderName"] as? String == "demo")
    }

    @Test func fileIsOwnerOnlyAndNoTempLeftBehind() throws {
        let dir = TempDir()
        ClaudeHookRunner.run(input: input("Stop"), directory: dir.url)
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.url.appendingPathComponent("abc-123.json").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        #expect(files(dir) == ["abc-123.json"])
    }

    @Test func sessionEndDeletesTheFile() {
        let dir = TempDir()
        ClaudeHookRunner.run(input: input("Stop"), directory: dir.url)
        #expect(files(dir) == ["abc-123.json"])
        ClaudeHookRunner.run(input: input("SessionEnd"), directory: dir.url)
        #expect(files(dir).isEmpty)
        // Ending a session that never wrote anything is a no-op.
        ClaudeHookRunner.run(input: input("SessionEnd", session: "never-seen"), directory: dir.url)
    }

    @Test func weirdSessionIdsAreSanitised() {
        #expect(ClaudeText.sanitizedID("../../etc/passwd") == "etcpasswd")
        #expect(ClaudeText.sanitizedID("a b\nc\u{0}d") == "abcd")
        #expect(ClaudeText.sanitizedID("../..") == nil)
        #expect(ClaudeText.sanitizedID("") == nil)
        #expect(ClaudeText.sanitizedID("é٣") == nil)
        #expect(ClaudeText.sanitizedID(String(repeating: "a", count: 200))?.count == 64)

        let dir = TempDir()
        ClaudeHookRunner.run(input: input("Stop", session: "../../escape/x y"), directory: dir.url)
        #expect(files(dir) == ["escapex y".filter { $0 != " " } + ".json"])
        let parent = dir.url.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("escape").path))
    }

    @Test func garbageInputWritesNothingAndReturnsNothing() {
        let dir = TempDir()
        let cases: [Data] = [
            Data(), Data("not json".utf8), Data("[]".utf8), Data("{}".utf8),
            input("Stop", session: "////"),                       // id sanitises to nothing
            input("SomethingNew"),
            Data(repeating: 0x7B, count: ClaudeHookRunner.maxInputBytes + 10),
        ]
        for c in cases { #expect(ClaudeHookRunner.run(input: c, directory: dir.url).isEmpty) }
        #expect(files(dir).isEmpty)
    }

    @Test func oversizedInputIsIgnoredEvenIfValidJSON() {
        let pad = String(repeating: "p", count: ClaudeHookRunner.maxInputBytes)
        let big = input("Stop", extra: "\"prompt\": \"\(pad)\"")
        #expect(ClaudeHookRunner.decide(input: big, now: Fixture.now) == .ignore)
    }

    @Test func missingCwdGivesEmptyFolder() {
        if case .write(_, let r) = ClaudeHookRunner.decide(input: input("Stop", cwd: nil), now: Fixture.now) {
            #expect(r.folderName == "")
        } else {
            Issue.record("expected a write")
        }
    }

    @Test func unwritableDirectoryDoesNotCrash() {
        let out = ClaudeHookRunner.run(input: input("Stop"), directory: URL(fileURLWithPath: "/dev/null/nope"))
        #expect(out.isEmpty)
    }

    @Test func standardInputReadIsCapped() throws {
        let dir = TempDir()
        let file = dir.write("in.bin", String(repeating: "z", count: ClaudeHookRunner.maxInputBytes * 2))
        let fd = open(file.path, O_RDONLY)
        defer { close(fd) }
        let data = SafeFileRead.readCapped(fd: fd, limit: ClaudeHookRunner.maxInputBytes, rejectOverflow: false)
        #expect(data?.count == ClaudeHookRunner.maxInputBytes)
    }

    // MARK: store + merge

    @Test func storeSkipsBadFilesAndUnknownStates() throws {
        let dir = TempDir()
        let good = ClaudeHookRecord(state: "waiting", folderName: "demo", updatedAt: 5)
        dir.write("good.json", String(data: try JSONEncoder().encode(good), encoding: .utf8) ?? "")
        dir.write("badstate.json", "{\"state\":\"dancing\",\"folderName\":\"x\",\"updatedAt\":1}")
        dir.write("broken.json", "{")
        dir.write("bad name.json", "{\"state\":\"idle\",\"folderName\":\"x\",\"updatedAt\":1}")
        dir.write("note.txt", "x")
        let records = ClaudeHookStore(directory: dir.url).read()
        #expect(Array(records.keys) == ["good"])
        #expect(records["good"] == good)
    }

    @Test func hookWinsOnlyWhileNewer() {
        let file = Date(timeIntervalSince1970: 1000)
        let session = ClaudeSession(id: "s", pid: 1, state: .working, folderName: "demo", updatedAt: file)
        let newer = ClaudeHookRecord(state: "waiting", folderName: "demo", updatedAt: 1001)
        let older = ClaudeHookRecord(state: "waiting", folderName: "demo", updatedAt: 999)
        #expect(ClaudeLiveSource.merge(sessions: [session], hooks: ["s": newer]).first?.state == .waiting)
        #expect(ClaudeLiveSource.merge(sessions: [session], hooks: ["s": older]).first?.state == .working)
        #expect(ClaudeLiveSource.merge(sessions: [session], hooks: ["s": ClaudeHookRecord(state: "idle", folderName: "", updatedAt: 1000)])
            .first?.state == .working)
    }

    @Test func hookAloneNeverCreatesASession() {
        let record = ClaudeHookRecord(state: "working", folderName: "demo", updatedAt: 1)
        #expect(ClaudeLiveSource.merge(sessions: [], hooks: ["ghost": record]).isEmpty)
    }

    @Test func hookWinsWhenTheFileHasNoTime() {
        let session = ClaudeSession(id: "s", pid: 1, state: .unknown, folderName: "", updatedAt: nil)
        let record = ClaudeHookRecord(state: "working", folderName: "demo", updatedAt: 1)
        let merged = ClaudeLiveSource.merge(sessions: [session], hooks: ["s": record]).first
        #expect(merged?.state == .working)
        #expect(merged?.folderName == "demo")
    }

    @Test func endToEndSourceMergesFilesFromDisk() throws {
        let sessions = TempDir()
        let hooks = TempDir()
        sessions.write("12.json", Fixture.sessionJSON(status: "idle", sessionId: "s12", updatedAtMillis: 1_800_000_100_000))
        ClaudeHookRunner.run(input: input("Notification", session: "s12"), directory: hooks.url,
                             now: Date(timeIntervalSince1970: 1_800_000_200))
        let source = ClaudeLiveSource(reader: Fixture.reader(sessions, alive: [12: Fixture.start]),
                                      hooks: ClaudeHookStore(directory: hooks.url))
        #expect(source.snapshot().first?.state == .waiting)
    }
}
