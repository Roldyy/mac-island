import Foundation
import Testing
@testable import PortKit

/// Lane W7C: brew discovery, the environment brew runs with, the cleanup preview and the model that drives it. All
/// with fakes: no brew is started, no network is used.
@Suite struct BrewLocatorTests {
    typealias Facts = BrewLocator.Facts

    static func facts(regular: Bool = true, executable: Bool = true, owner: UInt32 = 501, mode: UInt16 = 0o755) -> Facts {
        Facts(isRegularFile: regular, isExecutable: executable, ownerUID: owner, mode: mode)
    }

    @Test func theKnownPrefixesComeInOrderAndAHomebrewPrefixGoesFirst() {
        #expect(BrewLocator.candidates(environment: [:]) == ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
        #expect(BrewLocator.candidates(environment: ["HOMEBREW_PREFIX": "/Users/me/brew/"])
                == ["/Users/me/brew/bin/brew", "/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
        #expect(BrewLocator.candidates(environment: ["HOMEBREW_PREFIX": "/opt/homebrew"])
                == ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], "no duplicate")
    }

    @Test func aHostileOrRelativePrefixIsIgnored() {
        for bad in ["brew", "../etc", "/opt/../tmp/x", "/tmp/a\nb", "/tmp/$(whoami)", "/tmp/a;b", ""] {
            #expect(BrewLocator.candidates(environment: ["HOMEBREW_PREFIX": bad]) == BrewLocator.knownCandidates, "\(bad)")
        }
    }

    @Test func onlyAnExecutableRegularFileNobodyElseCanWriteIsTrusted() {
        let me: UInt32 = 501
        #expect(BrewLocator.isTrusted(Self.facts(), currentUID: me))
        #expect(BrewLocator.isTrusted(Self.facts(owner: 0), currentUID: me), "root-owned is fine")
        #expect(BrewLocator.isTrusted(Self.facts(owner: 502), currentUID: me) == false, "somebody else's file")
        #expect(BrewLocator.isTrusted(Self.facts(mode: 0o775), currentUID: me) == false, "group-writable")
        #expect(BrewLocator.isTrusted(Self.facts(mode: 0o757), currentUID: me) == false, "world-writable")
        #expect(BrewLocator.isTrusted(Self.facts(executable: false), currentUID: me) == false)
        #expect(BrewLocator.isTrusted(Self.facts(regular: false), currentUID: me) == false, "a directory or a socket")
    }

    @Test func locateTakesTheFirstTrustedCandidateAndSkipsTheOthers() {
        let table: [String: Facts] = [
            "/opt/homebrew/bin/brew": Self.facts(mode: 0o777),
            "/usr/local/bin/brew": Self.facts(),
        ]
        #expect(BrewLocator.locate(candidates: BrewLocator.knownCandidates, inspect: { table[$0] }, currentUID: 501)
                == "/usr/local/bin/brew")
        #expect(BrewLocator.locate(candidates: BrewLocator.knownCandidates, inspect: { _ in nil }, currentUID: 501) == nil)
        #expect(BrewLocator.locate(candidates: [], inspect: { _ in Self.facts() }, currentUID: 501) == nil)
    }

    @Test func inspectReadsTheRealModeAndOwner() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("brew-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("brew")
        try Data("#!/bin/sh\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let uid = UInt32(getuid())
        let good = try #require(BrewLocator.inspect(file.path))
        #expect(good.isRegularFile && good.isExecutable && good.ownerUID == uid && good.mode == 0o755)
        #expect(BrewLocator.isTrusted(good, currentUID: uid))
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: file.path)
        let loose = try #require(BrewLocator.inspect(file.path))
        #expect(BrewLocator.isTrusted(loose, currentUID: uid) == false)
        #expect(BrewLocator.inspect(dir.path)?.isRegularFile == false)
        #expect(BrewLocator.inspect(dir.appendingPathComponent("nope").path) == nil)
    }
}

@Suite struct HomebrewEnvironmentTests {
    @Test func brewRunsWithAFixedPathAndOnlyTheNamesItNeeds() {
        let base = [
            "PATH": "/tmp/evil:/usr/bin", "HOME": "/Users/me", "USER": "me", "TMPDIR": "/var/folders/x/T/",
            "LANG": "fr_FR.UTF-8", "SSH_AUTH_SOCK": "/tmp/agent",
            "https_proxy": "http://proxy:3128", "NO_PROXY": "localhost", "HOMEBREW_NO_AUTO_UPDATE": "1",
            "GITHUB_TOKEN": "secret", "AWS_SECRET_ACCESS_KEY": "secret", "ANTHROPIC_API_KEY": "secret",
            "DYLD_INSERT_LIBRARIES": "/tmp/x.dylib", "LD_PRELOAD": "/tmp/x.so", "SHELL": "/bin/zsh",
        ]
        let env = HomebrewEnvironment.environment(from: base)
        #expect(env["PATH"] == HomebrewEnvironment.fixedPath, "the app's PATH is never trusted")
        #expect(env["HOME"] == "/Users/me" && env["USER"] == "me" && env["TMPDIR"] == "/var/folders/x/T/")
        #expect(env["LANG"] == "fr_FR.UTF-8" && env["SSH_AUTH_SOCK"] == "/tmp/agent")
        #expect(env["https_proxy"] == "http://proxy:3128" && env["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        for leaked in ["GITHUB_TOKEN", "AWS_SECRET_ACCESS_KEY", "ANTHROPIC_API_KEY", "DYLD_INSERT_LIBRARIES",
                       "LD_PRELOAD", "SHELL", "NO_PROXY"] {
            #expect(env[leaked] == nil, "\(leaked) must not reach brew")
        }
    }

    @Test func theFixedPathHoldsOnlySystemAndHomebrewDirectories() {
        for part in HomebrewEnvironment.fixedPath.split(separator: ":") {
            #expect(part.hasPrefix("/") && !part.contains(".."), "\(part)")
            #expect(["/opt/homebrew", "/usr/local", "/usr", "/bin", "/sbin"].contains { part.hasPrefix($0) }, "\(part)")
        }
    }
}

@Suite struct HomebrewCleanupParseTests {
    static let dryRun = """
    Would remove: /Users/me/Library/Caches/Homebrew/downloads/abc--ffmpeg-7.1.tar.gz (45.2MB)
    Would remove: /opt/homebrew/Cellar/node/24.0.0 (2,611 files, 71.3MB)
    Would remove: /Users/me/Library/Caches/Homebrew/downloads/abc--ffmpeg-7.1.tar.gz (45.2MB)
    Would remove: relative/path (1KB)
    Would remove: /opt/homebrew/../etc/passwd (1KB)
    ==> This operation would free approximately 116.5MB of disk space.
    """

    @Test func theDryRunIsReadEntryByEntryAndOnlySafePathsCount() {
        let preview = HomebrewCleanup.parse(Self.dryRun)
        #expect(preview.entries.map(\.path) == [
            "/Users/me/Library/Caches/Homebrew/downloads/abc--ffmpeg-7.1.tar.gz",
            "/opt/homebrew/Cellar/node/24.0.0",
        ], "a duplicate, a relative path and a `..` path are dropped")
        #expect(preview.entries.map(\.detail) == ["45.2MB", "2,611 files, 71.3MB"])
        #expect(preview.freeable == "116.5MB")
        #expect(preview.isEmpty == false)
    }

    @Test func anEmptyOrUnrelatedOutputIsAnEmptyPreview() {
        #expect(HomebrewCleanup.parse("").isEmpty)
        #expect(HomebrewCleanup.parse("Warning: nothing to do\n").isEmpty)
        #expect(HomebrewCleanup.parse("").freeable == nil)
    }

    @Test func aLineWithoutASizeStillCounts() {
        let preview = HomebrewCleanup.parse("Would remove: /opt/homebrew/Cellar/foo/1.0\n")
        #expect(preview.entries == [HomebrewCleanup.Entry(path: "/opt/homebrew/Cellar/foo/1.0", detail: "")])
    }

    @Test func theCommandsAreFixedArgumentArraysWithNoShellAndNoPruneAll() {
        let preview = HomebrewCleanup.previewCommand(brewPath: "/opt/homebrew/bin/brew")
        let run = HomebrewCleanup.runCommand(brewPath: "/opt/homebrew/bin/brew")
        #expect(preview == HomebrewCommand(executable: "/opt/homebrew/bin/brew", arguments: ["cleanup", "--dry-run"]))
        #expect(run == HomebrewCommand(executable: "/opt/homebrew/bin/brew", arguments: ["cleanup"]))
        for command in [preview, run] {
            #expect(!command.arguments.contains("-c") && !command.arguments.contains { $0.hasPrefix("--prune") })
            #expect(!command.arguments.contains("-s") && !command.arguments.contains("--scrub"))
            #expect(!command.executable.hasSuffix("sh"))
        }
    }
}

@Suite struct HomebrewUpgradePreviewTests {
    static func update(_ name: String, from old: String, to new: String, pinned: Bool = false,
                       kind: HomebrewPackageKind = .formula) -> HomebrewPackageUpdate {
        HomebrewPackageUpdate(kind: kind, name: name, installedVersions: [old], currentVersion: new, isPinned: pinned)
    }

    @Test func everyOutdatedPackageIsListedSortedWithItsVersions() {
        let lines = HomebrewUpgradePreview.lines([
            Self.update("node", from: "24.0.0", to: "24.1.0"),
            Self.update("ffmpeg", from: "7.0", to: "7.1"),
            Self.update("Firefox", from: "130", to: "131", kind: .cask),
        ])
        #expect(lines == ["ffmpeg : 7.0 → 7.1", "Firefox : 130 → 131", "node : 24.0.0 → 24.1.0"])
    }

    @Test func pinnedPackagesAreLeftOutAsBrewLeavesThemOut() {
        let lines = HomebrewUpgradePreview.lines([Self.update("python@3.12", from: "1", to: "2", pinned: true),
                                                  Self.update("gh", from: "2.0", to: "2.1")])
        #expect(lines == ["gh : 2.0 → 2.1"])
    }

    @Test func aLongListIsCutWithTheNumberOfTheOthers() {
        let many = (0..<15).map { Self.update(String(format: "pkg%02d", $0), from: "1", to: "2") }
        let lines = HomebrewUpgradePreview.lines(many)
        #expect(lines.count == 13 && lines.last == "… et 3 autres")
        #expect(HomebrewUpgradePreview.lines(Array(many.prefix(13))).last == "… et 1 autre")
        #expect(HomebrewUpgradePreview.lines(Array(many.prefix(12))).count == 12, "exactly the limit: no tail line")
    }

    @Test func theMessageKeepsTheSentenceAndAppendsTheListOnlyWhenThereIsOne() {
        #expect(HomebrewUpgradePreview.message(base: "Base.", updates: []) == "Base.")
        #expect(HomebrewUpgradePreview.message(base: "Base.", updates: [Self.update("gh", from: "1", to: "2")])
                == "Base.\n\ngh : 1 → 2")
    }
}

@MainActor
@Suite struct HomebrewCleanupModelTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [HomebrewCommand] = []
        var all: [HomebrewCommand] { lock.lock(); defer { lock.unlock() }; return stored }
        func add(_ command: HomebrewCommand) { lock.lock(); stored.append(command); lock.unlock() }
    }

    nonisolated static let brew = "/opt/homebrew/bin/brew"

    nonisolated static let output = """
    Would remove: /Users/me/Library/Caches/Homebrew/downloads/a.tar.gz (10MB)
    Would remove: /opt/homebrew/Cellar/node/24.0.0 (100 files, 20MB)
    ==> This operation would free approximately 30MB of disk space.
    """

    func model(calls: Calls, brew: @escaping @MainActor () -> String? = { HomebrewCleanupModelTests.brew },
               busy: @escaping @MainActor () -> Bool = { false },
               dryRun: HomebrewCleanupModel.RunResult = .init(status: 0, output: HomebrewCleanupModelTests.output, timedOut: false),
               real: HomebrewCleanupModel.RunResult = .init(status: 0, output: "", timedOut: false),
               delay: Duration? = nil) -> HomebrewCleanupModel {
        HomebrewCleanupModel(locate: brew, run: { command, _ in
            calls.add(command)
            if let delay { try? await Task.sleep(for: delay) }
            return command.arguments.contains("--dry-run") ? dryRun : real
        }, managerBusy: busy)
    }

    @Test func theFirstStepIsTheDryRunAndRemovesNothing() async {
        let calls = Calls()
        let m = model(calls: calls)
        await m.preview()
        #expect(calls.all == [HomebrewCleanup.previewCommand(brewPath: Self.brew)])
        guard case let .preview(shown) = m.phase else { Issue.record("not a preview: \(m.phase)"); return }
        #expect(shown.entries.count == 2 && shown.freeable == "30MB")
    }

    @Test func nothingRunsWithoutAPreviewTheSecondStepNeedsTheFirst() async {
        let calls = Calls()
        let m = model(calls: calls)
        await m.confirm()
        #expect(calls.all.isEmpty && m.phase == .idle)
    }

    @Test func confirmingTheShownPreviewRunsTheRealCleanupOnceWithTheSameBrew() async {
        let calls = Calls()
        let m = model(calls: calls)
        await m.preview()
        await m.confirm()
        await m.confirm()
        #expect(calls.all == [HomebrewCleanup.previewCommand(brewPath: Self.brew),
                              HomebrewCleanup.runCommand(brewPath: Self.brew)], "one dry run, one real run, never two")
        #expect(m.phase == .finished(HomebrewCleanupText.freed("30MB")))
    }

    @Test func anEmptyPreviewCannotBeConfirmed() async {
        let calls = Calls()
        let m = model(calls: calls, dryRun: .init(status: 0, output: "", timedOut: false))
        await m.preview()
        #expect(m.phase == .preview(HomebrewCleanup.Preview(entries: [], freeable: nil)))
        await m.confirm()
        #expect(calls.all.count == 1, "only the dry run")
    }

    @Test func aBusyBrewBlocksBothStepsAndAMissingBrewIsReported() async {
        let calls = Calls()
        let busy = model(calls: calls, busy: { true })
        await busy.preview()
        #expect(calls.all.isEmpty && busy.phase == .idle)

        let missing = model(calls: calls, brew: { nil })
        await missing.preview()
        #expect(missing.phase == .brewMissing && calls.all.isEmpty)
    }

    @Test func aBrewThatChangedBetweenTheStepsIsNotRunBlindly() async {
        let calls = Calls()
        var current = Self.brew
        let m = model(calls: calls, brew: { current })
        await m.preview()
        current = "/usr/local/bin/brew"
        await m.confirm()
        #expect(calls.all.count == 1, "the real run only ever uses the brew the preview came from")
        guard case .preview = m.phase else { Issue.record("the preview should stay: \(m.phase)"); return }
    }

    @Test func aBrewBusyAtConfirmTimeBlocksTheRealRun() async {
        let calls = Calls()
        var busy = false
        let m = model(calls: calls, busy: { busy })
        await m.preview()
        busy = true
        await m.confirm()
        #expect(calls.all.count == 1)
    }

    @Test func failuresAndTimeoutsAreShownNotHidden() async {
        let failing = model(calls: Calls(), dryRun: .init(status: 1, output: "Error: disk is full\nmore", timedOut: false))
        await failing.preview()
        #expect(failing.phase == .failed("Error: disk is full"))

        let slow = model(calls: Calls(), dryRun: .init(status: -1, output: "", timedOut: true))
        await slow.preview()
        #expect(slow.phase == .failed(HomebrewCleanupText.timedOut))

        let realFails = model(calls: Calls(), real: .init(status: 1, output: "Error: permission denied", timedOut: false))
        await realFails.preview()
        await realFails.confirm()
        #expect(realFails.phase == .failed("Error: permission denied"))
    }

    @Test func cancelDropsAPreviewAndALateAnswerIsIgnored() async {
        let calls = Calls()
        let m = model(calls: calls, delay: .milliseconds(80))
        let task = Task { await m.preview() }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(m.phase == .previewing)
        m.cancel()
        await task.value
        #expect(m.phase == .idle, "the answer that arrived after the cancel changed nothing")
        await m.confirm()
        #expect(calls.all.count == 1)
    }
}
