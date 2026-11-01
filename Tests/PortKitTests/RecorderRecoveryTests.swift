import Foundation
import Testing
@testable import PortKit

/// Lane W4B (recorder): the journal, the launch recovery and the temp-then-rename of a direct save, on temporary
/// folders. The movie itself is never opened: "does it play" is a fake closure, the real one reads a file only.
@Suite(.serialized) struct RecorderRecoveryTests {
    /// A recordings root and a person's folder, both temporary and removed afterwards.
    final class Bench {
        let root: URL
        let folder: URL
        let manager = FileManager.default

        init() throws {
            let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("mis-recorder-\(UUID().uuidString)", isDirectory: true)
            root = base.appendingPathComponent("Recordings", isDirectory: true)
            folder = base.appendingPathComponent("Movies", isDirectory: true)
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        var base: URL { root.deletingLastPathComponent() }
        var journal: RecorderJournal { RecorderJournal(directory: root) }
        var destination: URL { folder.appendingPathComponent("recovered.mov") }
        func cleanup() { try? manager.removeItem(at: base) }

        /// A take folder with a master of these bytes.
        @discardableResult
        func makeTake(bytes: Data = Data("fragmented movie".utf8)) throws -> (name: String, folder: URL) {
            let name = RecorderSupport.takeFolderName(id: UUID())
            let take = root.appendingPathComponent(name, isDirectory: true)
            try manager.createDirectory(at: take, withIntermediateDirectories: true)
            if !bytes.isEmpty { try bytes.write(to: take.appendingPathComponent(RecorderSupport.takeVideoName)) }
            return (name, take)
        }

        func names(in directory: URL) -> [String] {
            ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        }
    }

    // MARK: Journal

    @Test func theJournalHoldsTheTakeUntilItIsSettled() throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let journal = bench.journal
        #expect(journal.load() == nil && !bench.manager.fileExists(atPath: journal.url.path))
        journal.noteTake(folderName: "take-A", now: Date(timeIntervalSince1970: 100))
        #expect(journal.load()?.take == "take-A" && journal.load()?.startedAt == Date(timeIntervalSince1970: 100))
        journal.settleTake(folderName: "take-B")
        #expect(journal.load()?.take == "take-A", "another take's settle changes nothing")
        journal.settleTake(folderName: "take-A")
        #expect(journal.load() == nil, "settled with nothing else owed: the file is gone")
        #expect(!bench.manager.fileExists(atPath: journal.url.path))
    }

    @Test func theJournalKeepsTheLastFiftyStagedPathsAndSurvivesASettle() throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let journal = bench.journal
        journal.noteTake(folderName: "take-A")
        for index in 0..<60 { journal.noteStaged(path: "/x/.macisland-partial-\(index)") }
        let entry = try #require(journal.load())
        #expect(entry.staged.count == RecorderJournal.maxStaged)
        #expect(entry.staged.first == "/x/.macisland-partial-10" && entry.staged.last == "/x/.macisland-partial-59")
        journal.settleTake(folderName: "take-A")
        #expect(journal.load()?.staged.count == 50 && journal.load()?.take == nil, "staged files stay owed")
        journal.clear()
        #expect(journal.load() == nil)
    }

    @Test func theJournalFileIsNotATake() throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        bench.journal.noteTake(folderName: "x")
        #expect(RecorderSupport.takeID(fromFolderName: RecorderJournal.fileName) == nil,
                "the upstream sweep and `takes()` never read it as a recording")
    }

    // MARK: Recovery

    @Test func withNoJournalNothingIsTouched() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let take = try bench.makeTake()
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                                 isPlayable: { _ in true })
        #expect(outcome == nil)
        #expect(bench.manager.fileExists(atPath: take.folder.path), "a take nobody journaled is the sweep's business")
        #expect(bench.names(in: bench.folder).isEmpty)
    }

    @Test func aHalfRecordedTakeThatPlaysIsSavedIntoThePersonsFolderAndOnlyOnce() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let bytes = Data("a recording cut at the last fragment".utf8)
        let take = try bench.makeTake(bytes: bytes)
        bench.journal.noteTake(folderName: take.name)
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                                 isPlayable: { _ in true })
        #expect(outcome?.recovered == bench.destination && outcome?.discardedTake == false)
        #expect((try? Data(contentsOf: bench.destination)) == bytes, "the recording, byte for byte")
        #expect(bench.names(in: bench.folder) == ["recovered.mov"], "no staged leftover beside it")
        #expect(!bench.manager.fileExists(atPath: take.folder.path), "the take is gone once saved")
        #expect(bench.journal.load() == nil, "the journal is cleared")
        let again = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                               isPlayable: { _ in true })
        #expect(again == nil, "idempotent: a second launch has nothing to do")
    }

    @Test func aTakeThatDoesNotPlayIsDeleted() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let take = try bench.makeTake()
        bench.journal.noteTake(folderName: take.name)
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                                 isPlayable: { _ in false })
        #expect(outcome?.recovered == nil && outcome?.discardedTake == true)
        #expect(!bench.manager.fileExists(atPath: take.folder.path))
        #expect(bench.names(in: bench.folder).isEmpty)
        #expect(bench.journal.load() == nil)
    }

    @Test func anEmptyMasterIsDeletedWithoutAskingWhetherItPlays() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let take = try bench.makeTake(bytes: Data())
        bench.journal.noteTake(folderName: take.name)
        let asked = Box(false)
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                                 isPlayable: { _ in asked.value = true; return true })
        #expect(outcome?.discardedTake == true && !asked.value)
        #expect(!bench.manager.fileExists(atPath: take.folder.path))
    }

    @Test func aTakeThatIsAlreadyGoneLeavesNothingToDo() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        bench.journal.noteTake(folderName: RecorderSupport.takeFolderName(id: UUID()))
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                                 isPlayable: { _ in true })
        #expect(outcome == RecorderRecovery.Outcome())
        #expect(bench.journal.load() == nil)
    }

    @Test func aStagedFileTheCrashLeftIsDeletedButOnlyOneWithOurHiddenPrefix() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let ours = bench.folder.appendingPathComponent("\(RecorderSupport.stagingPrefix)\(UUID().uuidString).mov")
        let legacy = bench.folder.appendingPathComponent(".vorssaint-partial-\(UUID().uuidString).gif")
        let theirs = bench.folder.appendingPathComponent("holiday.mov")
        let lookalike = bench.folder.appendingPathComponent("partial-\(UUID().uuidString).mov")
        for url in [ours, legacy, theirs, lookalike] { try Data("x".utf8).write(to: url) }
        for url in [ours, legacy, theirs, lookalike] { bench.journal.noteStaged(path: url.path) }
        bench.journal.noteStaged(path: bench.folder.appendingPathComponent("\(RecorderSupport.stagingPrefix)gone").path)
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                                 isPlayable: { _ in true })
        #expect(outcome?.removedStagedFiles == 2)
        #expect(!bench.manager.fileExists(atPath: ours.path) && !bench.manager.fileExists(atPath: legacy.path))
        #expect(bench.manager.fileExists(atPath: theirs.path), "a file of the person's is never deleted, even if journaled")
        #expect(bench.manager.fileExists(atPath: lookalike.path))
        #expect(bench.journal.load() == nil)
    }

    @Test func aJournaledNameThatIsNotATakeFolderIsIgnored() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let innocent = bench.base.appendingPathComponent("Important", isDirectory: true)
        try bench.manager.createDirectory(at: innocent, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: innocent.appendingPathComponent(RecorderSupport.takeVideoName))
        for name in ["../Important", "Important", "/etc", "take-not-a-uuid"] {
            bench.journal.noteTake(folderName: name)
            _ = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                           isPlayable: { _ in true })
            #expect(bench.manager.fileExists(atPath: innocent.path), "\(name)")
        }
        #expect(bench.names(in: bench.folder).isEmpty)
    }

    @Test func aSymbolicLinkInPlaceOfATakeFolderIsNeverFollowed() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let target = bench.base.appendingPathComponent("Elsewhere", isDirectory: true)
        try bench.manager.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: target.appendingPathComponent(RecorderSupport.takeVideoName))
        let name = RecorderSupport.takeFolderName(id: UUID())
        try bench.manager.createSymbolicLink(at: bench.root.appendingPathComponent(name), withDestinationURL: target)
        bench.journal.noteTake(folderName: name)
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { bench.destination },
                                                 isPlayable: { _ in true })
        #expect(outcome?.recovered == nil && outcome?.discardedTake == false)
        #expect(bench.manager.fileExists(atPath: target.appendingPathComponent(RecorderSupport.takeVideoName).path))
        #expect(bench.names(in: bench.folder).isEmpty)
    }

    @Test func whenTheFolderCannotBeWrittenTheTakeStaysAndTheJournalIsCleared() async throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let take = try bench.makeTake()
        bench.journal.noteTake(folderName: take.name)
        let missing = bench.base.appendingPathComponent("NoSuchFolder/recovered.mov")
        let outcome = await RecorderRecovery.run(journal: bench.journal, root: bench.root, destination: { missing },
                                                 isPlayable: { _ in true })
        #expect(outcome?.recovered == nil && outcome?.discardedTake == false)
        #expect(bench.manager.fileExists(atPath: take.folder.path), "nothing is lost: the 24 h sweep decides")
        #expect(bench.journal.load() == nil, "and the next launch does not retry forever")
    }

    // MARK: Temp-then-rename of a direct save

    @Test func aDirectSaveIsStagedBesideTheDestinationThenRenamed() throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let bytes = Data("finished recording".utf8)
        let take = try bench.makeTake(bytes: bytes)
        let value = RecorderTakeStore.Take(id: try #require(RecorderSupport.takeID(fromFolderName: take.name)), folder: take.folder)
        let seen = Box<[URL]>([])
        let saved = RecorderSupport.stagedObserver
        RecorderSupport.stagedObserver = { seen.value.append($0) }
        defer { RecorderSupport.stagedObserver = saved }
        try RecorderTakeStore.shared.saveDirectly(value, to: bench.destination)
        #expect((try? Data(contentsOf: bench.destination)) == bytes)
        #expect(bench.names(in: bench.folder) == ["recovered.mov"], "no hidden staged file is left")
        #expect(!bench.manager.fileExists(atPath: take.folder.path))
        #expect(seen.value.count == 1, "the staged path was journaled before anything was written to it")
        let staged = try #require(seen.value.first)
        #expect(staged.deletingLastPathComponent().standardizedFileURL == bench.folder.standardizedFileURL)
        #expect(staged.lastPathComponent.hasPrefix(RecorderSupport.stagingPrefix) && staged.pathExtension == "mov",
                "a hidden sibling of the destination, so the rename is on the same volume")
    }

    @Test func aFailedDirectSaveLeavesNoPartialFileAndKeepsTheTake() throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let take = try bench.makeTake()
        let value = RecorderTakeStore.Take(id: try #require(RecorderSupport.takeID(fromFolderName: take.name)), folder: take.folder)
        let missing = bench.base.appendingPathComponent("NoSuchFolder/saved.mov")
        #expect(throws: (any Error).self) { try RecorderTakeStore.shared.saveDirectly(value, to: missing) }
        #expect(bench.manager.fileExists(atPath: take.folder.appendingPathComponent(RecorderSupport.takeVideoName).path))
        #expect(bench.names(in: bench.folder).isEmpty)
    }

    @Test func aDirectSaveNeverReplacesAFileThatIsAlreadyThere() throws {
        let bench = try Bench()
        defer { bench.cleanup() }
        let take = try bench.makeTake()
        let value = RecorderTakeStore.Take(id: try #require(RecorderSupport.takeID(fromFolderName: take.name)), folder: take.folder)
        try Data("the person's own file".utf8).write(to: bench.destination)
        #expect(throws: (any Error).self) { try RecorderTakeStore.shared.saveDirectly(value, to: bench.destination) }
        #expect((try? Data(contentsOf: bench.destination)) == Data("the person's own file".utf8))
        #expect(bench.names(in: bench.folder) == ["recovered.mov"], "the staged copy is removed")
        #expect(bench.manager.fileExists(atPath: take.folder.path), "the take is kept for another try")
    }

    // MARK: Hooks and wiring

    @MainActor @Test func theUpstreamRecorderExposesTheJournalHooks() {
        let service = ScreenRecorderService.shared
        let savedStarted = service.onTakeStarted
        let savedSettled = service.onTakeSettled
        defer { service.onTakeStarted = savedStarted; service.onTakeSettled = savedSettled }
        let events = Box<[String]>([])
        service.onTakeStarted = { events.value.append("started \($0.id)") }
        service.onTakeSettled = { events.value.append("settled \($0.id)") }
        let take = RecorderTakeStore.Take(id: UUID(), folder: URL(fileURLWithPath: "/nonexistent"))
        service.onTakeStarted?(take)
        service.onTakeSettled?(take)
        #expect(events.value == ["started \(take.id)", "settled \(take.id)"])
    }

    @Test func theUpstreamServiceCallsTheHooksWhereATakeBeginsAndEnds() throws {
        let service = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent(
            "Services/Recorder/ScreenRecorderService.swift"), encoding: .utf8)
        #expect(service.components(separatedBy: "onTakeStarted?(take)").count == 2, "once, before the stream starts")
        #expect(service.components(separatedBy: "onTakeSettled?(").count == 3,
                "when a start fails and when a stop is over (written, failed or handed to the editor)")
    }

    @Test func theRecoveryHasACallerInTheLaneAndTheLaneRunsItOnceAtBind() throws {
        let lane = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/Recorder.swift"),
                              encoding: .utf8)
        #expect(lane.contains("recoverAtLaunchLive()\n    }"), "bind(into:) runs it at launch")
        #expect(lane.contains("recover: { RecorderLane.recoverAtLaunchLive() }"), "and so does every start")
        #expect(lane.contains("guard !didRecover else { return }"), "once")
        #expect(lane.contains("guard journal.load() != nil else { return }"), "a Mac with no journal touches no file")
    }
}
