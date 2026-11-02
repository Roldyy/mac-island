import AppKit
import Darwin
import Foundation
import Testing
@testable import TerminalFeature

private func makeProfile(_ name: String) -> TerminalColorProfile {
    TerminalColorProfile(
        id: UUID(), name: name,
        ansi: (0..<16).map { TerminalRGB(0.1, Double($0) / 15, 0.5) },
        foreground: TerminalRGB(0.9, 0.9, 0.9), background: TerminalRGB(0, 0, 0.1),
        cursor: TerminalRGB(1, 1, 1), selection: TerminalRGB(0.2, 0.2, 0.6),
        fontName: nil, fontSize: nil, importedAt: Date(timeIntervalSince1970: 1_700_000_000))
}

private func freshDefaults() -> UserDefaults {
    let suite = "terminal-hardening-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// A scratch folder whose path is already resolved (no /var -> /private/var symlink to trip comparisons).
private func scratchFolder() throws -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("term-hardening-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(base.path, &buffer) != nil else { return base }  // the kernel's own spelling (/private/var/...)
    return URL(fileURLWithPath: String(cString: buffer))
}

private func writeITermColors(to url: URL, blue: Double = 0.2) throws {
    let dict: [String: Any] = Dictionary(uniqueKeysWithValues: (0..<16).map { i in
        ("Ansi \(i) Color", ["Red Component": Double(i) / 15, "Green Component": 0.5, "Blue Component": blue, "Color Space": "sRGB"] as [String: Any])
    })
    try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
}

// MARK: Names

@Suite struct TerminalProfileNameCapTests {
    private let zalgo = "a" + String(repeating: "\u{0301}", count: 450_000)

    @Test func oneCharacterWithHundredsOfThousandsOfMarksStaysSmall() {
        let name = TerminalColorProfile.sanitizedName(zalgo)
        #expect(name.utf8.count <= TerminalColorProfile.maxNameBytes)
        #expect(name.unicodeScalars.count <= TerminalColorProfile.maxCombiningRun + 1)
        #expect(name.unicodeScalars.first == "a")
    }

    @Test func manyAccentedCharactersAreBoundedInScalarsAndBytes() {
        let long = String(repeating: "é\u{0301}\u{0302}\u{0303}\u{0304}", count: 500) + String(repeating: "😀", count: 500)
        let name = TerminalColorProfile.sanitizedName(long)
        #expect(name.count <= TerminalColorProfile.maxNameLength)
        #expect(name.unicodeScalars.count <= TerminalColorProfile.maxNameScalars)
        #expect(name.utf8.count <= TerminalColorProfile.maxNameBytes)
        #expect(String(data: Data(name.utf8), encoding: .utf8) == name)  // cut on a scalar boundary: valid UTF-8
    }

    @Test func ordinaryAccentsAndEmojiSurvive() {
        #expect(TerminalColorProfile.sanitizedName("Café nuit ☾ 😀") == "Café nuit ☾ 😀")
        #expect(TerminalColorProfile.sanitizedName("e\u{0301}") == "e\u{0301}")
    }

    @Test func zalgoProfileNeverMakesTheLibraryUnreadable() throws {
        let defaults = freshDefaults()
        let store = TerminalProfileStore(defaults: defaults)
        var library = TerminalProfileLibrary()
        library.add(makeProfile("Avant"))
        #expect(store.save(library))
        var evil = makeProfile(TerminalColorProfile.sanitizedName(zalgo))
        evil.ansi = evil.ansi.map { TerminalRGB($0.red * 0.5, $0.green, $0.blue) }
        library.add(evil)
        #expect(store.save(library))
        let back = store.load()
        #expect(back.profiles.count == 2)
        #expect((defaults.data(forKey: TerminalProfileStore.key)?.count ?? .max) < 20_000)
    }
}

// MARK: Encode refuses what decode would reject

@Suite struct TerminalProfileEncodeLimitTests {
    @Test func oversizedLibraryIsRefusedAndTheStoredOneStaysUntouched() throws {
        let defaults = freshDefaults()
        let store = TerminalProfileStore(defaults: defaults)
        var good = TerminalProfileLibrary()
        good.add(makeProfile("Garde"))
        #expect(store.save(good))
        let before = defaults.data(forKey: TerminalProfileStore.key)

        // A name that never went through sanitizedName: the library init does not sanitise.
        let huge = TerminalProfileLibrary(profiles: [makeProfile(String(repeating: "x", count: 300_000))])
        #expect(TerminalProfileLibraryCodec.encode(huge) == nil)
        #expect(store.save(huge) == false)
        #expect(defaults.data(forKey: TerminalProfileStore.key) == before)
        #expect(store.load().profiles.map(\.name) == ["Garde"])
    }

    @Test func whatEncodeAcceptsDecodeAccepts() throws {
        var library = TerminalProfileLibrary()
        for index in 0..<TerminalProfileLibrary.maxProfiles { library.add(makeProfile("P\(index)" + String(repeating: "é", count: 50))) }
        let data = try #require(TerminalProfileLibraryCodec.encode(library))
        #expect(data.count <= TerminalProfileLibraryCodec.maxBytes)
        #expect(TerminalProfileLibraryCodec.decode(data).profiles.count == library.profiles.count)
    }
}

// MARK: Import: what the file is, and where it is read

@Suite struct TerminalProfileImportFileTests {
    @Test func regularFileIsRead() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Nuit.itermcolors")
        try writeITermColors(to: url)
        #expect(try TerminalColorProfileParser.read(url: url).profile.name == "Nuit")
    }

    @Test func symlinkToARegularFileIsFollowedAndJudgedByItsTarget() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appendingPathComponent("Vrai.itermcolors")
        try writeITermColors(to: real)
        let link = folder.appendingPathComponent("Lien.itermcolors")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(try TerminalColorProfileParser.read(url: link).foundColors == 16)
    }

    @Test func namedPipeIsRefusedWithoutHanging() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fifo = folder.appendingPathComponent("tube.terminal")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: TerminalColorProfileError.notARegularFile) { try TerminalColorProfileParser.read(url: fifo) }
    }

    @Test func directoryDeviceAndLinkToADeviceAreRefused() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = folder.appendingPathComponent("dossier.terminal")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        #expect(throws: TerminalColorProfileError.notARegularFile) { try TerminalColorProfileParser.read(url: directory) }
        let device = folder.appendingPathComponent("zero.itermcolors")
        try FileManager.default.createSymbolicLink(at: device, withDestinationURL: URL(fileURLWithPath: "/dev/zero"))
        #expect(throws: TerminalColorProfileError.notARegularFile) { try TerminalColorProfileParser.read(url: device) }
    }

    @Test func oversizedFileIsRefusedFromItsSizeAlone() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let big = folder.appendingPathComponent("gros.itermcolors")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(TerminalColorProfileParser.maxFileBytes) + 10)  // sparse
        try handle.close()
        #expect(throws: TerminalColorProfileError.fileTooLarge) { try TerminalColorProfileParser.read(url: big) }
    }

    @MainActor @Test func backgroundImportShowsTheSameResultAsTheSynchronousOne() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Aube.itermcolors")
        try writeITermColors(to: url)
        let model = TerminalProfilesModel(store: TerminalProfileStore(defaults: freshDefaults()), session: IdleSession())
        await model.importFileInBackground(at: url)
        #expect(model.pending?.profile.name == "Aube" && model.errorMessage == nil)

        let fifo = folder.appendingPathComponent("tube.terminal")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        await model.importFileInBackground(at: fifo)
        #expect(model.pending == nil && model.errorMessage?.contains("fichier ordinaire") == true)
    }
}

@MainActor
private final class IdleSession: TerminalRestarting {
    var restarts = 0
    var decision: TerminalRestartDecision = .restart
    func restartDecision() -> TerminalRestartDecision { decision }
    func restartWithActiveProfile() { restarts += 1 }
}

@MainActor
@Suite struct TerminalProfileSaveFailureTests {
    @Test func aLibraryThatCannotBeKeptShowsAFrenchErrorAndChangesNothing() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Nuit.itermcolors")
        try writeITermColors(to: url)
        let session = IdleSession()
        let store = TerminalProfileStore(defaults: freshDefaults(), maxBytes: 200)  // far too small for any profile
        let model = TerminalProfilesModel(store: store, session: session)
        model.importFile(at: url)
        model.applyPending()
        #expect(model.errorMessage?.contains("Rien n’a été modifié") == true)
        #expect(session.restarts == 0)
        #expect(store.load().profiles.isEmpty && model.library.profiles.isEmpty)
        #expect(model.pending != nil)  // the user can retry after freeing room
    }
}

// MARK: The real restart flow, with real shells under a PTY

/// Wraps the real terminator and records what the session asked of it.
private final class SpyTerminator: ShellTerminating, @unchecked Sendable {
    private let lock = NSLock()
    private var real = TerminalShellTerminator()
    private var targets: [ShellTarget] = []
    private var results: [(pid_t, ShellEndOutcome)] = []

    init() {
        real.completion = { [weak self] target, outcome in
            guard let self else { return }
            self.lock.withLock { self.results.append((target.shellPid, outcome)) }
        }
    }

    var hangUps: [ShellTarget] { lock.withLock { targets } }
    func outcome(of pid: pid_t) -> ShellEndOutcome? { lock.withLock { results.first { $0.0 == pid }?.1 } }

    func hangUp(shellPid: pid_t, foregroundGroup: pid_t?) -> ShellTarget {
        let target = real.hangUp(shellPid: shellPid, foregroundGroup: foregroundGroup)
        lock.withLock { targets.append(target) }
        return target
    }

    func reap(_ target: ShellTarget) { real.reap(target) }
}

@MainActor
private final class Launches {
    var directories: [String] = []
    var pids: [pid_t] = []
}

@MainActor
@Suite(.serialized) struct TerminalSessionRestartFlowTests {
    private func settle(_ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return condition()
    }

    private func gone(_ pid: pid_t) -> Bool { kill(pid, 0) == -1 && errno == ESRCH }

    /// The first shell starts in `folder` (it cds there, as a user would); later ones start where they are told.
    private func makeSession(
        folder: URL, launches: Launches, store: TerminalProfileStore, spy: SpyTerminator,
        foreground: @escaping (Int32) -> pid_t? = TerminalProcessInfo.foregroundGroup(masterFd:)
    ) -> TerminalSession {
        TerminalSession(
            startShell: { view, directory in
                launches.directories.append(directory)
                let first = launches.directories.count == 1
                view.startProcess(
                    executable: "/bin/sh", args: first ? ["-c", "cd \"$1\" && exec sleep 600", "sh", folder.path] : ["-c", "exec sleep 600"],
                    environment: nil, execName: nil, currentDirectory: directory)
                launches.pids.append(view.process.shellPid)
            },
            activeProfile: { store.activeProfile },
            foregroundGroup: foreground,
            terminator: spy)
    }

    @Test func applyEndsTheOldShellForRealAndStartsTheNewOneInTheSameFolderWithTheColours() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Nuit.itermcolors")
        try writeITermColors(to: file)
        let store = TerminalProfileStore(defaults: freshDefaults())
        let spy = SpyTerminator()
        let launches = Launches()
        let session = makeSession(folder: folder, launches: launches, store: store, spy: spy)
        let model = TerminalProfilesModel(store: store, session: session)

        let oldView = session.ensureRunning()
        let oldPid = try #require(launches.pids.first)
        #expect(oldPid > 0)
        #expect(await settle { TerminalProcessInfo.currentDirectory(of: oldPid) == folder.path })

        model.importFile(at: file)
        model.applyPending()
        #expect(model.confirmation == nil)  // a lone shell: restarts at once
        #expect(model.statusMessage?.contains("redémarré") == true)
        #expect(launches.pids.count == 2)
        let newPid = launches.pids[1]
        defer { kill(newPid, SIGKILL) }
        #expect(newPid != oldPid)
        #expect(launches.directories[1] == folder.path)  // same folder the old shell was in
        #expect(spy.hangUps.count == 1 && spy.hangUps[0].shellPid == oldPid)

        #expect(await settle { spy.outcome(of: oldPid) != nil })  // the reaper finished
        let outcome = try #require(spy.outcome(of: oldPid))
        // Which one depends on who wins the race (our wait, SwiftTerm's monitor) and on the runner's signal mask.
        #expect([.reaped, .alreadyGone, .killed].contains(outcome))
        #expect(await settle { gone(oldPid) })  // the old shell and its program are really gone

        let newView = session.ensureRunning()
        #expect(newView !== oldView && session.hasSession)
        let wanted = try #require(store.activeProfile)
        #expect(newView.nativeBackgroundColor == wanted.background.nsColor)
        #expect(newView.nativeForegroundColor == wanted.foreground.nsColor)
        #expect(oldView.nativeBackgroundColor != wanted.background.nsColor)
        #expect(await settle { TerminalProcessInfo.currentDirectory(of: newPid) == folder.path })
        #expect(launches.pids.count == 2)  // ensureRunning did not start a third one
    }

    @Test func aProgramInFrontAsksFirstAndOnlyAnAnswerEndsIt() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Nuit.itermcolors")
        try writeITermColors(to: file)
        let store = TerminalProfileStore(defaults: freshDefaults())
        let spy = SpyTerminator()
        let launches = Launches()
        let bogusGroup: pid_t = 2_000_000_000  // no such process group: killpg answers ESRCH, nothing else is touched
        let session = makeSession(folder: folder, launches: launches, store: store, spy: spy, foreground: { _ in bogusGroup })
        let model = TerminalProfilesModel(store: store, session: session)

        _ = session.ensureRunning()
        let oldPid = try #require(launches.pids.first)
        defer { kill(oldPid, SIGKILL) }

        model.importFile(at: file)
        model.applyPending()
        #expect(model.confirmation?.process == "un programme")
        #expect(spy.hangUps.isEmpty && launches.pids.count == 1 && store.activeProfile == nil)

        model.cancelRestart()
        #expect(spy.hangUps.isEmpty && launches.pids.count == 1 && !gone(oldPid))

        model.applyPending()
        model.confirmRestart()
        #expect(launches.pids.count == 2)
        defer { kill(launches.pids[1], SIGKILL) }
        #expect(spy.hangUps.count == 1 && spy.hangUps[0].foregroundGroup == bogusGroup)
        #expect(await settle { spy.outcome(of: oldPid) != nil })
        #expect(await settle { gone(oldPid) })
        #expect(store.activeProfile?.name == "Nuit")
    }
}
