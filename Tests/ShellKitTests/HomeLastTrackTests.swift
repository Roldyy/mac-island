import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

/// Records every call instead of touching NSWorkspace.
@MainActor
final class FakePlayerLauncher: PlayerLaunching {
    var installed: [String: URL] = [:]
    var running: Set<String> = []
    private(set) var launched: [URL] = []
    private(set) var webPages: [URL] = []

    func applicationURL(bundleID: String) -> URL? { installed[bundleID] }
    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
    func launch(appAt url: URL) { launched.append(url) }
    func openWebPage(_ url: URL) { webPages.append(url) }

    static let spotifyURL = URL(fileURLWithPath: "/Applications/Spotify.app")
    static let musicURL = URL(fileURLWithPath: "/System/Applications/Music.app")
}

private func tempStore() -> (store: LastTrackStore, cleanup: () -> Void) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mis-last-track-\(UUID().uuidString)")
    return (LastTrackStore(url: folder.appendingPathComponent("Data/last-track")),
            { try? FileManager.default.removeItem(at: folder) })
}

private func sampleRecord(title: String = "Reason", bundle: String = "com.spotify.client",
                          at date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> LastTrackRecord {
    LastTrackRecord(title: title, artist: "Bonobo", album: "Migration", playerBundleID: bundle, timestamp: date,
                    artworkJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]))
}

@Suite struct LastTrackRecordTests {
    @Test func aRecordSurvivesTheDisk() throws {
        let bench = tempStore()
        defer { bench.cleanup() }
        let record = sampleRecord()
        #expect(bench.store.save(record))
        #expect(bench.store.load() == record)
        let url = try #require(bench.store.url)
        let mode = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        #expect(mode.intValue == 0o600)
        bench.store.clear()
        #expect(bench.store.load() == nil)
        #expect(bench.store.modificationDate() == nil)
    }

    @Test func aCorruptFileIsIgnoredNotFatal() throws {
        let bench = tempStore()
        defer { bench.cleanup() }
        let url = try #require(bench.store.url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for garbage in ["", "not json", "{}", #"{"version":2,"title":"x","artist":"","album":"","playerBundleID":"a","timestamp":1}"#,
                        #"{"version":1,"title":"","artist":"","album":"","playerBundleID":"a","timestamp":1}"#,
                        #"{"version":1,"title":"x","artist":"","album":"","playerBundleID":"","timestamp":1}"#,
                        #"{"version":1,"title":"x","artist":"","album":"","playerBundleID":"a"}"#] {
            try Data(garbage.utf8).write(to: url)
            #expect(bench.store.load() == nil, "\(garbage)")
        }
    }

    @Test func aHugeFileIsIgnoredAndNeverWritten() throws {
        let bench = tempStore()
        defer { bench.cleanup() }
        var huge = sampleRecord()
        huge.artworkJPEG = Data(repeating: 7, count: LastTrackRecord.maxFileBytes)
        #expect(huge.encoded() == nil)
        #expect(!bench.store.save(huge))
        let url = try #require(bench.store.url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: LastTrackRecord.maxFileBytes + 1).write(to: url)
        #expect(bench.store.load() == nil)
    }

    @Test func textIsClipped() {
        let record = LastTrackRecord(title: String(repeating: "a", count: 5_000), playerBundleID: "x", timestamp: Date())
        #expect(record.title.count == LastTrackRecord.maxTextLength)
    }

    /// The literal `NowPlayingFeature` writes (its own test decodes the same text): one side drifting fails here.
    @Test func theFileContractMatchesTheWriter() throws {
        let json = #"{"version":1,"title":"Reason","artist":"Bonobo","album":"Migration","playerBundleID":"com.spotify.client","timestamp":1700000000,"artwork":"/9j/2Q=="}"#
        let record = try #require(LastTrackRecord.decode(Data(json.utf8)))
        #expect(record.title == "Reason" && record.artist == "Bonobo" && record.album == "Migration")
        #expect(record.playerBundleID == "com.spotify.client")
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(record.artworkJPEG == Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }
}

@Suite struct LastTrackRelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func text(_ secondsAgo: TimeInterval) -> String {
        LastTrackRelativeTime.text(since: now.addingTimeInterval(-secondsAgo), now: now)
    }

    @Test func frenchStrings() {
        #expect(text(5) == "à l’instant")
        #expect(text(-30) == "à l’instant")
        #expect(text(60) == "il y a 1 min")
        #expect(text(59 * 60) == "il y a 59 min")
        #expect(text(3_600) == "il y a 1 h")
        #expect(text(2 * 3_600 + 100) == "il y a 2 h")
        #expect(text(23 * 3_600) == "il y a 23 h")
        #expect(text(30 * 3_600) == "hier")
        #expect(text(3 * 86_400) == "il y a 3 j")
        #expect(text(6 * 86_400 + 5) == "il y a 6 j")
    }

    @Test func olderThanAWeekIsADate() {
        let old = text(30 * 86_400)
        #expect(old.hasPrefix("le "))
        #expect(!old.contains("il y a"))
    }
}

@MainActor
@Suite struct LastTrackPlayerTests {
    @Test func whichPlayerOpens() {
        #expect(MusicPlayerTarget(bundleID: "com.spotify.client") == MusicPlayerTarget(bundleID: nil))
        #expect(MusicPlayerTarget(bundleID: nil).bundleID == "com.spotify.client")
        #expect(MusicPlayerTarget(bundleID: "").bundleID == "com.spotify.client")
        #expect(MusicPlayerTarget(bundleID: "com.apple.Music").bundleID == "com.apple.Music")
        #expect(MusicPlayerTarget(bundleID: "com.apple.Music").name == "Musique")
        let other = MusicPlayerTarget(bundleID: "org.videolan.vlc")
        #expect(other.bundleID == "org.videolan.vlc" && other.name == nil)
    }

    @Test func aMissingSpotifyOpensTheDownloadPage() {
        let launcher = FakePlayerLauncher()
        let plan = PlayerOpenPlan.resolve(playerBundleID: nil, launcher: launcher)
        #expect(plan == .installPage(url: URL(string: "https://www.spotify.com/download")!))
        #expect(plan.help == "Spotify n’est pas installé : ouvrir la page d’installation")
        plan.perform(with: launcher)
        #expect(launcher.webPages == [URL(string: "https://www.spotify.com/download")!])
        #expect(launcher.launched.isEmpty)
    }

    @Test func anInstalledPlayerIsLaunched() {
        let launcher = FakePlayerLauncher()
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL,
                              "com.apple.Music": FakePlayerLauncher.musicURL,
                              "org.videolan.vlc": URL(fileURLWithPath: "/Applications/VLC.app")]
        let spotify = PlayerOpenPlan.resolve(playerBundleID: nil, launcher: launcher)
        #expect(spotify == .launch(name: "Spotify", bundleID: "com.spotify.client", appURL: FakePlayerLauncher.spotifyURL))
        #expect(spotify.title == "Ouvrir Spotify")
        let music = PlayerOpenPlan.resolve(playerBundleID: "com.apple.Music", launcher: launcher)
        #expect(music == .launch(name: "Musique", bundleID: "com.apple.Music", appURL: FakePlayerLauncher.musicURL))
        let vlc = PlayerOpenPlan.resolve(playerBundleID: "org.videolan.vlc", launcher: launcher)
        #expect(vlc.title == "Ouvrir VLC")
        music.perform(with: launcher)
        #expect(launcher.launched == [FakePlayerLauncher.musicURL])
        #expect(launcher.webPages.isEmpty)
    }

    @Test func aGonePlayerFallsBackToSpotifyThenToTheDownloadPage() {
        let launcher = FakePlayerLauncher()
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL]
        let viaSpotify = PlayerOpenPlan.resolve(playerBundleID: "org.videolan.vlc", launcher: launcher)
        #expect(viaSpotify == .launch(name: "Spotify", bundleID: "com.spotify.client", appURL: FakePlayerLauncher.spotifyURL))
        launcher.installed = [:]
        let page = PlayerOpenPlan.resolve(playerBundleID: "org.videolan.vlc", launcher: launcher)
        #expect(page == .installPage(url: MusicPlayerTarget.spotifyInstallURL))
    }
}

@MainActor
@Suite struct LastTrackModelTests {
    private func make(_ bench: (store: LastTrackStore, cleanup: () -> Void), _ defaults: UserDefaults,
                      _ launcher: FakePlayerLauncher, now: @escaping () -> Date = { Date() }) -> LastTrackModel {
        LastTrackModel(defaults: defaults, store: bench.store, launcher: launcher, now: now)
    }

    @Test func rememberingIsOnByDefaultAndLoadsTheFile() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let model = make(store, defaults.defaults, FakePlayerLauncher())
        #expect(model.isEnabled)
        #expect(model.record == nil)
        store.store.save(sampleRecord())
        model.refresh()
        #expect(model.record == sampleRecord())
        store.store.clear()
        model.refresh()
        #expect(model.record == nil)
    }

    @Test func switchingTheFlagOffForgetsAndDeletesTheFile() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let model = make(store, defaults.defaults, FakePlayerLauncher())
        store.store.save(sampleRecord())
        model.refresh()
        #expect(model.record != nil)
        defaults.defaults.set(false, forKey: LastTrackModel.flagKey)
        #expect(!model.isEnabled)
        model.refresh()
        #expect(model.record == nil)
        #expect(store.store.modificationDate() == nil)
        // A file that was never loaded is deleted too.
        store.store.save(sampleRecord())
        model.refresh()
        #expect(store.store.modificationDate() == nil)
    }

    @Test func theFileIsDecodedOnlyWhenItChanged() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let model = make(store, defaults.defaults, FakePlayerLauncher())
        store.store.save(sampleRecord(title: "One"))
        model.refresh()
        let first = model.record
        model.refresh()
        #expect(model.record == first)
        // Corrupt on top of a good record: the stale one goes away rather than staying forever.
        if let url = store.store.url {
            try? Data("garbage".utf8).write(to: url)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        }
        model.refresh()
        #expect(model.record == nil)
    }

    @Test func clickOpensTheRecordedPlayer() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let launcher = FakePlayerLauncher()
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL, "com.apple.Music": FakePlayerLauncher.musicURL]
        let model = make(store, defaults.defaults, launcher)
        store.store.save(sampleRecord(bundle: "com.apple.Music"))
        model.refresh()
        #expect(model.help == "Ouvrir Musique")
        model.open()
        #expect(launcher.launched == [FakePlayerLauncher.musicURL])
    }

    @Test func clickWithNothingKnownOpensSpotifyOrTheInstallPage() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let launcher = FakePlayerLauncher()
        let model = make(store, defaults.defaults, launcher)
        model.refresh()
        #expect(model.help == "Spotify n’est pas installé : ouvrir la page d’installation")
        #expect(model.callToAction == "Ouvrir Spotify")
        model.open()
        #expect(launcher.webPages == [MusicPlayerTarget.spotifyInstallURL])
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL]
        model.open()
        #expect(launcher.launched == [FakePlayerLauncher.spotifyURL])
    }

    @Test func theInstalledAnswerIsReusedForAWhileThenRefreshed() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let launcher = FakePlayerLauncher()
        var clock = Date(timeIntervalSince1970: 1_000)
        let model = make(store, defaults.defaults, launcher) { clock }
        model.refresh()
        #expect(model.help.contains("pas installé"))
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL]
        clock = clock.addingTimeInterval(2)
        model.refresh()
        #expect(model.help.contains("pas installé"))
        clock = clock.addingTimeInterval(LastTrackModel.planLifetime)
        model.refresh()
        #expect(model.help == "Ouvrir Spotify")
    }

    @Test func playPressesPlayWhenTheRecordedPlayerRunsAndLaunchesItOtherwise() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let launcher = FakePlayerLauncher()
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL]
        let model = make(store, defaults.defaults, launcher)
        store.store.save(sampleRecord())
        model.refresh()
        var sent: [HomeTransport] = []
        model.play { sent.append($0) }
        #expect(sent.isEmpty)
        #expect(launcher.launched == [FakePlayerLauncher.spotifyURL])
        launcher.running = ["com.spotify.client"]
        model.play { sent.append($0) }
        #expect(sent == [.playPause])
        #expect(launcher.launched.count == 1)
    }

    @Test func playWithSpotifyMissingOpensTheInstallPageAndSendsNothing() {
        let store = tempStore()
        let defaults = TestDefaults.make()
        defer { store.cleanup(); defaults.cleanup() }
        let launcher = FakePlayerLauncher()
        let model = make(store, defaults.defaults, launcher)
        var sent: [HomeTransport] = []
        model.play { sent.append($0) }
        #expect(sent.isEmpty)
        #expect(launcher.webPages == [MusicPlayerTarget.spotifyInstallURL])
    }
}

@Suite struct LastTrackSettingsRowTests {
    @Test func theSettingsRowUsesTheKeyTheModelAndTheWriterRead() throws {
        let island = try #require(SettingsLive.controls(for: "island"))
        let row = try #require(island.extras.first { $0.key == LastTrackModel.flagKey })
        #expect(LastTrackModel.flagKey == "notchRememberLastTrack")
        #expect(row.title == "Mémoriser la dernière lecture")
        #expect(row.hint?.contains("Reste sur ce Mac") == true)
        if case .toggle(let defaultValue, _) = row.kind { #expect(defaultValue) } else { Issue.record("not a toggle") }
    }
}
