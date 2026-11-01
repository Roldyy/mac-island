import Foundation
import Testing
@testable import PortKit

/// Lane W5-D safety: the private-API probe, the lock seam, the Finder flags and their temporary mode, and the source
/// gates (no prompt API, no network at start, no shell string). Fakes only: no framework, no Finder, no `defaults`.
@MainActor
@Suite(.serialized) struct LauncherSafetyTests {
    // MARK: Probe (fails closed, French reason)

    @Test func aMissingAppearanceSymbolBlocksTheDarkModeToggleWithAFrenchReason() {
        for missing in QuickToggleCapability.appearance.symbols {
            let report = QuickToggleProbe.evaluate(isPresent: { $0 != missing }, lockInstalled: true)
            #expect(!report.allows(.appearance), "\(missing) missing -> blocked")
            #expect(report.allows(.lockScreen))
            #expect(report.blockingReasons.count == 1)
            let reason = report.blockingReasons.first ?? ""
            #expect(reason.contains("macOS") && reason.contains("Apparence"), "French, with the way out: \(reason)")
        }
    }

    @Test func aMissingLockerOnlyDegradesBecauseTheScreenSaverStandsIn() {
        let report = QuickToggleProbe.evaluate(isPresent: { _ in true }, lockInstalled: false)
        #expect(!report.allows(.lockScreen) && report.allows(.appearance))
        #expect(report.blockingReasons.isEmpty, "nothing blocks: the fallback is public")
        #expect(report.findings.first?.reason.contains("économiseur") == true)
    }

    @Test func everythingPresentIsSilentAndNothingPresentNamesBothCapabilities() {
        #expect(QuickToggleProbe.evaluate(isPresent: { _ in true }, lockInstalled: true).findings.isEmpty)
        let none = QuickToggleProbe.evaluate(isPresent: { _ in false }, lockInstalled: false)
        #expect(none.findings.map(\.capability) == [.appearance, .lockScreen])
        #expect(none.findings.allSatisfy { !$0.reason.isEmpty })
    }

    @Test func theLiveLookupAnswersForTheAppearanceSymbolsOnlyAndNeverLoadsTheLoginFramework() {
        #expect(QuickToggleCapability.appearance.symbols == ["SLSGetAppearanceThemeLegacy", "SLSSetAppearanceThemeLegacy"])
        #expect(QuickTogglesService.isPrivateSymbolAvailable("SACLockScreenImmediate") == false,
                "the lock symbol is the app's, not this file's")
        #expect(QuickTogglesService.isPrivateSymbolAvailable("NotASymbol") == false)
        // The real answer depends on the macOS under test: only that it is a Bool and the probe agrees with it.
        let present = QuickToggleCapability.appearance.symbols.allSatisfy(QuickTogglesService.isPrivateSymbolAvailable)
        #expect(QuickToggleProbe.live.allows(.appearance) == present)
    }

    // MARK: Lock seam (one private path, in the app)

    @Test func theLockSeamUsesTheAppsLockerAndFallsBackToNothingWhenAbsent() {
        defer { QuickToggleSeams.installLock(nil) }
        QuickToggleSeams.installLock(nil)
        #expect(QuickToggleSeams.performLock() == nil, "no locker: the caller uses the screen saver")
        #expect(!QuickToggleSeams.hasLock)
        var calls = 0
        QuickToggleSeams.installLock { calls += 1; return true }
        #expect(QuickToggleSeams.hasLock)
        #expect(QuickToggleSeams.performLock() == true && calls == 1)
        QuickToggleSeams.installLock { calls += 1; return false }
        #expect(QuickToggleSeams.performLock() == false && calls == 2, "a failed chain is reported, the caller falls back")
        QuickToggleSeams.installLock(nil)
        #expect(QuickToggleSeams.performLock() == nil)
    }

    @Test func thePublicInstallerIsTheSameSeam() {
        defer { QuickToggleSeams.installLock(nil) }
        PortQuickToggles.installLockScreen { true }
        #expect(QuickToggleSeams.hasLock)
        PortQuickToggles.installLockScreen(nil)
        #expect(!QuickToggleSeams.hasLock)
    }

    @Test func onlyThePrivateLockFileOfTheAppNamesTheLockSymbol() throws {
        for file in PortSourceScrubTests.files {
            for (index, line) in file.lines.enumerated()
            where !line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") && line.contains("SACLockScreenImmediate") {
                Issue.record("a second private lock path: \(file.path):\(index + 1)")
            }
        }
        let root = PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/MacIsland")
        let privateFile = try String(contentsOf: root.appendingPathComponent("PrivateLockScreen.swift"), encoding: .utf8)
        #expect(privateFile.contains("SACLockScreenImmediate") && privateFile.contains("displaysleepnow"))
        let actions = try String(contentsOf: root.appendingPathComponent("SystemActions.swift"), encoding: .utf8)
        #expect(actions.contains("PortQuickToggles.installLockScreen") && actions.contains("AppScreenLock.lock()"),
                "the island button and the ported toggle share one chain")
        #expect(!actions.contains("LoginFrameworkScreenLock()"), "the chain is built once, in PrivateLockScreen.swift")
    }

    // MARK: Finder flags

    final class FakeFinder {
        var values: [String: Bool]
        var writes: [String] = []
        var syncs = 0
        var restarts = 0
        var restartResult = true
        var onWrite: ((String) -> Void)?

        init(_ values: [String: Bool] = [:]) { self.values = values }

        var store: FinderPreferenceStore {
            FinderPreferenceStore(
                read: { [self] in values[$0] },
                write: { [self] key, value in
                    onWrite?(key)
                    writes.append(key)
                    if let value { values[key] = value } else { values.removeValue(forKey: key) }
                },
                synchronize: { [self] in syncs += 1 })
        }

        func restart() -> Bool { restarts += 1; return restartResult }
    }

    static let hidden = QuickTogglesSupport.showAllFilesKey
    static let icons = QuickTogglesSupport.createDesktopKey

    @Test func anExplicitToggleWritesTheKeyAndRestartsTheFinderOnceWithoutAnyJournalByDefault() {
        PortHostFixture.isolated { defaults in
            let finder = FakeFinder([Self.hidden: false])
            let ok = FinderFlags.apply(key: Self.hidden, to: true, prefs: finder.store, defaults: defaults,
                                       restart: finder.restart)
            #expect(ok)
            #expect(finder.values[Self.hidden] == true && finder.writes == [Self.hidden] && finder.syncs == 1)
            #expect(finder.restarts == 1)
            #expect(FinderFlags.journal(defaults).isEmpty && !FinderFlags.owesRestore(defaults: defaults),
                    "no temporary mode: nothing is journaled, nothing is owed")
        }
    }

    @Test func aFailedRestartIsReportedButThePreferenceStaysWritten() {
        PortHostFixture.isolated { defaults in
            let finder = FakeFinder()
            finder.restartResult = false
            let ok = FinderFlags.apply(key: Self.icons, to: false, prefs: finder.store, defaults: defaults,
                                       restart: finder.restart)
            #expect(!ok)
            #expect(finder.values[Self.icons] == false, "the next Finder launch applies it")
        }
    }

    @Test func theTemporaryModeJournalsTheOriginalBeforeTheKeyIsWrittenAndKeepsTheFirstOne() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: FinderFlags.temporaryKey)
            let finder = FakeFinder([Self.hidden: false])
            var journalAtWrite: [String: String] = [:]
            finder.onWrite = { _ in journalAtWrite = FinderFlags.journal(defaults) }
            _ = FinderFlags.apply(key: Self.hidden, to: true, prefs: finder.store, defaults: defaults, restart: finder.restart)
            #expect(journalAtWrite == [Self.hidden: "0"], "the note exists before the preference is touched")
            _ = FinderFlags.apply(key: Self.hidden, to: false, prefs: finder.store, defaults: defaults, restart: finder.restart)
            _ = FinderFlags.apply(key: Self.hidden, to: true, prefs: finder.store, defaults: defaults, restart: finder.restart)
            #expect(FinderFlags.journal(defaults) == [Self.hidden: "0"], "the first original wins, never an intermediate value")
            // A key that was never set is journaled as absent.
            _ = FinderFlags.apply(key: Self.icons, to: false, prefs: finder.store, defaults: defaults, restart: finder.restart)
            #expect(FinderFlags.journal(defaults)[Self.icons] == "absent")
            #expect(FinderFlags.owesRestore(defaults: defaults))
        }
    }

    @Test func stoppingInTheTemporaryModeGivesTheOriginalsBackWithOneFinderRestart() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: FinderFlags.temporaryKey)
            let finder = FakeFinder([Self.hidden: false])
            _ = FinderFlags.apply(key: Self.hidden, to: true, prefs: finder.store, defaults: defaults, restart: finder.restart)
            _ = FinderFlags.apply(key: Self.icons, to: false, prefs: finder.store, defaults: defaults, restart: finder.restart)
            finder.restarts = 0
            let outcome = FinderFlags.restoreTemporary(prefs: finder.store, defaults: defaults, restart: finder.restart)
            #expect(outcome == .restored)
            #expect(finder.values[Self.hidden] == false, "restored to the original value")
            #expect(finder.values[Self.icons] == nil, "a key that was absent is removed again")
            #expect(finder.restarts == 1, "one restart for the whole restore")
            #expect(FinderFlags.journal(defaults).isEmpty && !FinderFlags.owesRestore(defaults: defaults))
            // A second stop owes nothing and touches nothing.
            finder.writes.removeAll()
            #expect(FinderFlags.restoreTemporary(prefs: finder.store, defaults: defaults, restart: finder.restart) == .nothingOwed)
            #expect(finder.writes.isEmpty && finder.restarts == 1)
        }
    }

    @Test func withoutTheTemporaryModeAStopRestoresNothingAndNeverRestartsTheFinder() {
        PortHostFixture.isolated { defaults in
            let finder = FakeFinder([Self.hidden: false])
            _ = FinderFlags.apply(key: Self.hidden, to: true, prefs: finder.store, defaults: defaults, restart: finder.restart)
            finder.restarts = 0
            finder.writes.removeAll()
            #expect(FinderFlags.restoreTemporary(prefs: finder.store, defaults: defaults, restart: finder.restart) == .nothingOwed)
            #expect(finder.values[Self.hidden] == true, "the user's choice stays")
            #expect(finder.writes.isEmpty && finder.restarts == 0)
            // Even a stale journal is ignored when the temporary mode is off.
            defaults.set([Self.hidden: "0"], forKey: FinderFlags.journalKey)
            #expect(FinderFlags.restoreTemporary(prefs: finder.store, defaults: defaults, restart: finder.restart) == .nothingOwed)
            #expect(finder.values[Self.hidden] == true && finder.restarts == 0)
        }
    }

    @Test func aRestoreThatCannotRestartKeepsTheJournalForTheNextStartAndAnUnchangedValueNeedsNoRestart() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: FinderFlags.temporaryKey)
            let finder = FakeFinder([Self.hidden: false])
            _ = FinderFlags.apply(key: Self.hidden, to: true, prefs: finder.store, defaults: defaults, restart: finder.restart)
            finder.restarts = 0
            finder.restartResult = false
            #expect(FinderFlags.restoreTemporary(prefs: finder.store, defaults: defaults, restart: finder.restart) == .restartFailed)
            #expect(FinderFlags.owesRestore(defaults: defaults), "kept: the next start pays it")
            // The user put the original back by hand meanwhile: nothing changes, so no restart and the note is dropped.
            finder.values[Self.hidden] = false
            finder.restarts = 0
            finder.restartResult = true
            #expect(FinderFlags.restoreTemporary(prefs: finder.store, defaults: defaults, restart: finder.restart) == .nothingOwed)
            #expect(finder.restarts == 0 && !FinderFlags.owesRestore(defaults: defaults))
        }
    }

    @Test func aPermanentToggleDropsItsJournalEntryAndIsNeverRestored() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: FinderFlags.temporaryKey)
            let finder = FakeFinder([Self.hidden: false])
            _ = FinderFlags.apply(key: Self.hidden, to: true, prefs: finder.store, defaults: defaults, restart: finder.restart)
            defaults.set(false, forKey: FinderFlags.temporaryKey)
            _ = FinderFlags.apply(key: Self.hidden, to: false, prefs: finder.store, defaults: defaults, restart: finder.restart)
            #expect(FinderFlags.journal(defaults).isEmpty, "a choice made outside the temporary mode is the user's own")
        }
    }

    @Test func theServiceReadsTheFinderStateThroughTheSeam() {
        let saved = QuickToggleSeams.finderPrefs
        defer { QuickToggleSeams.finderPrefs = saved }
        let finder = FakeFinder([Self.hidden: true, Self.icons: false])
        QuickToggleSeams.finderPrefs = finder.store
        #expect(QuickTogglesService.shared.hiddenFilesShown)
        #expect(!QuickTogglesService.shared.desktopIconsShown)
        QuickToggleSeams.finderPrefs = FakeFinder().store
        #expect(!QuickTogglesService.shared.hiddenFilesShown, "absent: hidden files are not shown")
        #expect(QuickTogglesService.shared.desktopIconsShown, "absent: the desktop icons are shown")
    }

    @Test func stoppingWithoutTheTemporaryModeNeverEvenReachesThePreferences() {
        PortHostFixture.isolated { _ in
            let saved = QuickToggleSeams.finderPrefs
            defer { QuickToggleSeams.finderPrefs = saved }
            let finder = FakeFinder([Self.hidden: true])
            QuickToggleSeams.finderPrefs = finder.store
            LauncherLive.restoreOwedFinderFlags()
            LauncherLive.restoreOwedFinderFlagsAtQuit()
            #expect(finder.writes.isEmpty && finder.syncs == 0 && finder.restarts == 0)
        }
    }

    // MARK: Source gates

    private static let laneFiles = [
        "Bridge/Launcher.swift", "Services/QuickTools/QuickLauncherService.swift",
        "Services/QuickTools/QuickTogglesService.swift", "Services/QuickTools/QuickTogglesSupport.swift",
        "Services/RadialMenu/RadialMenuService.swift", "UI/Settings/RadialMenuSettings.swift",
        "UI/MenuPanel/QuickTogglesSection.swift", "UI/QuickLauncher/QuickLauncherView.swift",
    ]

    private static func code(of path: String) -> [(line: Int, text: Substring)] {
        guard let file = PortSourceScrubTests.files.first(where: { $0.path == path }) else { return [] }
        return file.lines.enumerated().compactMap { index, line in
            line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") ? nil : (index + 1, line)
        }
    }

    @Test func noLaneFileCallsAPromptApiOrReachesTheNetworkOrBuildsAShellString() {
        let banned = PortPromptScrubTests.banned + [
            "requestAccess(", "requestAuthorization(", "consentToAutomate(",
            "URLSession", "URLRequest", "NWConnection", "Process(", "NSAppleScript", "/bin/sh", "/bin/bash", "popen(",
            "posix_spawn", "execv",
        ]
        for path in Self.laneFiles {
            let lines = Self.code(of: path)
            #expect(!lines.isEmpty, "\(path) reads back")
            for (line, text) in lines where banned.contains(where: { text.contains($0) }) {
                Issue.record("\(path):\(line) uses a prompt, network or shell API: \(text)")
            }
        }
    }

    @Test func everyProcessTheLaneStartsIsAFixedPathWithAFixedArgumentArray() {
        for path in ["Services/QuickTools/QuickTogglesService.swift", "Bridge/Launcher.swift"] {
            for (line, text) in Self.code(of: path) where text.contains("Shell.run(") {
                #expect(text.contains("Shell.run(\"/"), "\(path):\(line) runs a computed path: \(text)")
                #expect(!text.contains("\\("), "\(path):\(line) interpolates into an argument: \(text)")
            }
        }
    }

    @Test func theFaviconFetchIsReachedOnlyFromTheExplicitButtonOfTheEditor() {
        var callers: [String] = []
        for file in PortSourceScrubTests.files where !file.path.hasPrefix("Bridge/") {
            for line in file.lines where line.contains("RadialMenuFaviconFetcher.fetchFavicon(") {
                callers.append(file.path)
            }
        }
        #expect(callers == ["UI/Settings/RadialMenuSettings.swift"], "one call site, a click in the item editor: \(callers)")
        for line in Self.code(of: "Bridge/Launcher.swift") {
            #expect(!line.text.contains("Favicon"), "the lane never fetches an icon by itself")
        }
    }
}
