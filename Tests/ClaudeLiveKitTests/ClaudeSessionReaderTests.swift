import Foundation
import Testing
@testable import ClaudeLiveKit

@Suite struct ClaudeSessionReaderTests {
    @Test func readsALiveSessionAndKeepsOnlyTheFolderName() {
        let dir = TempDir()
        dir.write("4242.json", Fixture.sessionJSON())
        let sessions = Fixture.reader(dir, alive: [4242: Fixture.start]).read()
        #expect(sessions.count == 1)
        #expect(sessions[0].pid == 4242)
        #expect(sessions[0].id == "sess-1")
        #expect(sessions[0].state == .working)
        #expect(sessions[0].folderName == "demo")
        #expect(sessions[0].entrypoint == "cli")
        #expect(sessions[0].updatedAt == Date(timeIntervalSince1970: 1_800_000_500))
    }

    @Test func mapsStatuses() {
        let dir = TempDir()
        dir.write("1.json", Fixture.sessionJSON(status: "idle"))
        dir.write("2.json", Fixture.sessionJSON(status: "waiting"))
        dir.write("3.json", Fixture.sessionJSON(status: "busy"))
        let alive: [Int32: Date] = [1: Fixture.start, 2: Fixture.start, 3: Fixture.start]
        let states = Fixture.reader(dir, alive: alive).read().map(\.state)
        #expect(states == [.idle, .waiting, .working])
    }

    @Test func unknownStatusIsUnknownNeverIdle() {
        let dir = TempDir()
        dir.write("7.json", Fixture.sessionJSON(status: "thinking-very-hard"))
        let sessions = Fixture.reader(dir, alive: [7: Fixture.start]).read()
        #expect(sessions.first?.state == .unknown)
    }

    @Test func missingStatusIsUnknown() {
        let dir = TempDir()
        dir.write("7.json", "{\"procStart\": \"\(Fixture.procStart())\"}")
        #expect(Fixture.reader(dir, alive: [7: Fixture.start]).read().first?.state == .unknown)
    }

    @Test func reusedPidIsRejected() {
        let dir = TempDir()
        dir.write("99.json", Fixture.sessionJSON())
        // Same pid now belongs to a process that started an hour later.
        let reader = Fixture.reader(dir, alive: [99: Fixture.start.addingTimeInterval(3600)])
        #expect(reader.read().isEmpty)
    }

    @Test func startTimeWithinToleranceIsAccepted() {
        let dir = TempDir()
        dir.write("99.json", Fixture.sessionJSON())
        #expect(Fixture.reader(dir, alive: [99: Fixture.start.addingTimeInterval(1)]).read().count == 1)
    }

    @Test func deadPidIsStale() {
        let dir = TempDir()
        dir.write("99.json", Fixture.sessionJSON())
        #expect(Fixture.reader(dir, alive: [:]).read().isEmpty)
    }

    @Test func missingOrUnparsableProcStartIsRejected() {
        let dir = TempDir()
        dir.write("1.json", "{\"status\": \"busy\"}")
        dir.write("2.json", Fixture.sessionJSON(procStart: "not a date"))
        #expect(Fixture.reader(dir, alive: [1: Fixture.start, 2: Fixture.start]).read().isEmpty)
    }

    @Test func malformedJSONIsSkippedWithoutAffectingOthers() {
        let dir = TempDir()
        dir.write("1.json", "{ this is not json")
        dir.write("2.json", "[1,2,3]")
        dir.write("3.json", Fixture.sessionJSON())
        let sessions = Fixture.reader(dir, alive: [1: Fixture.start, 2: Fixture.start, 3: Fixture.start]).read()
        #expect(sessions.map(\.pid) == [3])
    }

    @Test func oversizedFileIsRejected() {
        let dir = TempDir()
        let padding = String(repeating: "a", count: ClaudeSessionReader.maxFileBytes)
        dir.write("5.json", Fixture.sessionJSON().replacingOccurrences(of: "do not read me", with: padding))
        #expect(Fixture.reader(dir, alive: [5: Fixture.start]).read().isEmpty)
    }

    @Test func symlinkIsRejected() throws {
        let dir = TempDir()
        let target = dir.write("target.txt", Fixture.sessionJSON())
        try FileManager.default.createSymbolicLink(at: dir.url.appendingPathComponent("6.json"),
                                                   withDestinationURL: target)
        #expect(Fixture.reader(dir, alive: [6: Fixture.start]).read().isEmpty)
    }

    @Test func directoryNamedLikeASessionIsRejected() throws {
        let dir = TempDir()
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("8.json"),
                                                withIntermediateDirectories: false)
        #expect(Fixture.reader(dir, alive: [8: Fixture.start]).read().isEmpty)
    }

    @Test func oddFileNamesAreIgnored() {
        let dir = TempDir()
        for name in ["x.key", "10028.abc.key", "12345678.json", "0.json", "-1.json", "1.json.bak", ".json",
                     "٣.json", " 4.json", "4.JSON"] {
            dir.write(name, Fixture.sessionJSON())
        }
        let alive: [Int32: Date] = [1: Fixture.start, 4: Fixture.start, 3: Fixture.start]
        #expect(Fixture.reader(dir, alive: alive).read().isEmpty)
    }

    @Test func pathTraversalNameIsNotReachable() {
        // "../x.json" cannot be a directory entry, so it is checked at the name filter.
        #expect(ClaudeSessionReader.pid(fromFileName: "../x.json") == nil)
        #expect(ClaudeSessionReader.pid(fromFileName: "../1.json") == nil)
        #expect(ClaudeSessionReader.pid(fromFileName: "1/2.json") == nil)
        #expect(ClaudeSessionReader.pid(fromFileName: "1234567.json") == 1_234_567)
    }

    @Test func hugeCwdGivesABoundedFolderName() {
        let dir = TempDir()
        let long = "/" + String(repeating: "d", count: 12_000)
        dir.write("9.json", Fixture.sessionJSON(cwd: long))
        let session = Fixture.reader(dir, alive: [9: Fixture.start]).read().first
        #expect(session?.folderName.count == ClaudeText.maxFolderLength)
    }

    @Test func cwdNeverLeaksAParentPath() {
        #expect(ClaudeText.folderName(fromCwd: "/Users/a/b/proj/") == "proj")
        #expect(ClaudeText.folderName(fromCwd: "/") == "")
        #expect(ClaudeText.folderName(fromCwd: "") == "")
        #expect(ClaudeText.folderName(fromCwd: "/a/b\u{7}c").contains("\u{7}") == false)
    }

    @Test func strangeEntrypointAndSessionIdAreSanitised() {
        let dir = TempDir()
        dir.write("3.json", Fixture.sessionJSON(entrypoint: "../../evil path", sessionId: "a/b c"))
        let session = Fixture.reader(dir, alive: [3: Fixture.start]).read().first
        #expect(session?.entrypoint == nil)
        #expect(session?.id == "abc")
    }

    @Test func futureUpdatedAtIsClampedToNow() {
        let dir = TempDir()
        dir.write("3.json", Fixture.sessionJSON(updatedAtMillis: 9_999_999_999_000))
        #expect(Fixture.reader(dir, alive: [3: Fixture.start]).read().first?.updatedAt == Fixture.now)
    }

    @Test func missingDirectoryGivesNoSessions() {
        let reader = ClaudeSessionReader(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"),
                                         clock: { Fixture.now }, probe: FakeProbe(starts: [:]))
        #expect(reader.read().isEmpty)
    }

    @Test func procStartParsesPaddedDays() {
        #expect(ProcStart.parse("Wed Oct  7 09:05:03 2026") != nil)
        #expect(ProcStart.parse("Wed Oct 7 09:05:03 2026") == ProcStart.parse("Wed Oct  7 09:05:03 2026"))
        #expect(ProcStart.parse(String(repeating: "x", count: 500)) == nil)
    }

    @Test func systemProbeKnowsThisProcess() {
        let start = SystemProcessProbe().startTime(ofPID: getpid())
        #expect(start != nil)
        #expect(start.map { $0 <= Date() } == true)
        #expect(SystemProcessProbe().startTime(ofPID: Int32.max) == nil)
    }
}
