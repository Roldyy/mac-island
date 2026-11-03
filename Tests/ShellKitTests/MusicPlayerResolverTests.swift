import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

private let spotify = "com.spotify.client"
private let music = "com.apple.Music"
private let both: Set<String> = [spotify, music]

@Suite struct MusicPlayerResolverTests {
    private func resolve(playing: String? = nil, last: String? = nil, preferred: String = "", blocker: Bool = false,
                         replacement: String? = nil, installed: Set<String> = both) -> MusicPlayerResolver.Outcome {
        MusicPlayerResolver.resolve(playing: playing, last: last,
                                    settings: MusicPlayerSettings(preferred: preferred, blockerOn: blocker, replacementBundleID: replacement),
                                    isInstalled: { installed.contains($0) })
    }

    @Test func theAppPlayingNowWins() {
        #expect(resolve(playing: spotify, last: music, preferred: music) == .open(bundleID: spotify))
        #expect(resolve(playing: "com.example.Tidal", installed: both.union(["com.example.Tidal"])) == .open(bundleID: "com.example.Tidal"))
    }

    @Test func aStaleMusicTrackNeverBeatsTheChosenSpotify() {
        // The reported bug: last track from Apple Music, Spotify chosen.
        #expect(resolve(last: music, preferred: spotify) == .open(bundleID: spotify))
    }

    @Test func theBlockerNeverReturnsMusic() {
        #expect(resolve(last: music, blocker: true) == .open(bundleID: spotify))
        #expect(resolve(last: music, preferred: music, blocker: true) == .open(bundleID: spotify))
        #expect(resolve(playing: music, blocker: true) == .open(bundleID: spotify))
        #expect(resolve(last: "com.apple.iTunes", blocker: true, installed: both.union(["com.apple.iTunes"])) == .open(bundleID: spotify))
        #expect(resolve(last: music, blocker: true, installed: [music]) == .installPage(MusicPlayerResolver.spotifyInstallURL))
    }

    @Test func theBlockersReplacementComesBeforeSpotify() {
        #expect(resolve(last: music, blocker: true, replacement: "com.example.Tidal", installed: both.union(["com.example.Tidal"]))
                == .open(bundleID: "com.example.Tidal"))
    }

    @Test func aChosenPlayerThatIsMissingOpensItsInstallPage() {
        #expect(resolve(last: music, preferred: spotify, installed: [music]) == .installPage(MusicPlayerResolver.spotifyInstallURL))
        #expect(resolve(installed: []) == .installPage(MusicPlayerResolver.spotifyInstallURL))
    }

    @Test func nothingPlayingAndNoLastTrackOpensThePreferredPlayer() {
        #expect(resolve(preferred: music) == .open(bundleID: music))
        #expect(resolve(preferred: spotify) == .open(bundleID: spotify))
        #expect(resolve() == .open(bundleID: spotify))
    }

    @Test func automaticFollowsTheLastTrackWhenNothingForbidsIt() {
        #expect(resolve(last: music) == .open(bundleID: music))
    }

    @Test func settingsAreReadFromTheKeysThePagesWrite() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(spotify, forKey: "notchPreferredPlayer")
        bench.defaults.set(true, forKey: "musicBlockEnabled")
        bench.defaults.set("/Applications/Tidal.app", forKey: "musicBlockReplacementPath")
        let settings = MusicPlayerSettings.read(from: bench.defaults, bundleID: { $0 == "/Applications/Tidal.app" ? "com.example.Tidal" : nil })
        #expect(settings == MusicPlayerSettings(preferred: spotify, blockerOn: true, replacementBundleID: "com.example.Tidal"))
    }
}

@MainActor @Suite struct MusicClickPathTests {
    private func bench(preferred: String?, blocker: Bool, last: String?, installed: Set<String>)
        -> (model: LastTrackModel, launcher: FakePlayerLauncher, cleanup: () -> Void) {
        let defaults = TestDefaults.make()
        if let preferred { defaults.defaults.set(preferred, forKey: "notchPreferredPlayer") }
        defaults.defaults.set(blocker, forKey: "musicBlockEnabled")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mis-music-click-\(UUID().uuidString)")
        let store = LastTrackStore(url: folder.appendingPathComponent("Data/last-track"))
        if let last {
            store.save(LastTrackRecord(title: "T", artist: "A", album: "Al", playerBundleID: last,
                                       timestamp: Date(timeIntervalSince1970: 1_700_000_000), artworkJPEG: nil))
        }
        let launcher = FakePlayerLauncher()
        for id in installed {
            launcher.installed[id] = id == spotify ? FakePlayerLauncher.spotifyURL : FakePlayerLauncher.musicURL
        }
        let model = LastTrackModel(defaults: defaults.defaults, store: store, launcher: launcher)
        model.refresh()
        return (model, launcher, { defaults.cleanup(); try? FileManager.default.removeItem(at: folder) })
    }

    @Test func clickWithSpotifyChosenAndAMusicTrackOpensOnlySpotify() {
        let b = bench(preferred: spotify, blocker: false, last: music, installed: both)
        defer { b.cleanup() }
        b.model.open()
        #expect(b.launcher.launched == [FakePlayerLauncher.spotifyURL])
        #expect(b.launcher.webPages.isEmpty)
    }

    @Test func clickWithTheBlockerOnNeverLaunchesMusic() {
        let b = bench(preferred: nil, blocker: true, last: music, installed: both)
        defer { b.cleanup() }
        b.model.open()
        #expect(b.launcher.launched == [FakePlayerLauncher.spotifyURL])
        b.model.play { _ in }
        #expect(!b.launcher.launched.contains(FakePlayerLauncher.musicURL))
    }

    @Test func clickWithSpotifyMissingOpensTheInstallPageNotMusic() {
        let b = bench(preferred: spotify, blocker: true, last: music, installed: [music])
        defer { b.cleanup() }
        b.model.open()
        #expect(b.launcher.launched.isEmpty)
        #expect(b.launcher.webPages == [MusicPlayerTarget.spotifyInstallURL])
    }
}
