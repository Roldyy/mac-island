import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

/// A source driven by the test: the reading is whatever the test says, every call is counted.
@MainActor
final class FakeNowPlayingSource {
    var reading = HomeNowPlayingReading.none
    private(set) var refreshes = 0
    private(set) var openCalls: [Bool] = []
    private(set) var sent: [HomeTransport] = []
    private(set) var authorizations = 0
    private var observer: (@MainActor () -> Void)?

    var source: HomeNowPlayingSource {
        HomeNowPlayingSource(
            read: { [unowned self] in reading },
            refresh: { [unowned self] in refreshes += 1 },
            setOpen: { [unowned self] in openCalls.append($0) },
            send: { [unowned self] in sent.append($0) },
            authorize: { [unowned self] in authorizations += 1 },
            observe: { [unowned self] in observer = $0 })
    }

    /// The player read again: new reading, observers told (what the model does after each poll).
    func publish(_ next: HomeNowPlayingReading) {
        reading = next
        observer?()
    }
}

private let spotify = HomeNowPlayingReading.Player(bundleID: "com.spotify.client", name: "Spotify")

private func track(playing: Bool, title: String = "Reason", progress: Double? = 0.4) -> HomeTrack {
    HomeTrack(title: title, artist: "Bonobo", artworkData: Data([1, 2, 3]), isPlaying: playing, progress: progress,
              album: "Migration", position: 40, duration: 100, playerBundleID: spotify.bundleID, playerName: "Spotify")
}

@MainActor
@Suite struct HomeNowPlayingFeedTests {
    private func home(_ fake: FakeNowPlayingSource) -> (home: HomeModel, cleanup: () -> Void) {
        let bench = TestDefaults.make()
        let home = HomeModel(defaults: bench.defaults)
        home.attachNowPlaying(fake.source)
        return (home, bench.cleanup)
    }

    @Test func playingShowsTheLiveTrack() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.publish(HomeNowPlayingReading(access: .ready, track: track(playing: true), runningPlayer: spotify))
        #expect(home.track == track(playing: true))
        #expect(home.nowPlayingNotice == nil)
    }

    @Test func pausedShowsTheLivePausedTrackNotTheStoredOne() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.publish(HomeNowPlayingReading(access: .ready, track: track(playing: false, title: "Paused one"),
                                           runningPlayer: spotify))
        #expect(home.track?.title == "Paused one")
        #expect(home.track?.isPlaying == false)
        #expect(home.nowPlayingNotice == nil)
    }

    @Test func stoppedOrNoPlayerFallsBackToTheStoredLastTrack() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.publish(HomeNowPlayingReading(access: .ready, track: track(playing: true), runningPlayer: spotify))
        // Spotify quit: no track, no player. The card then falls back to `home.lastTrack` (the stored track).
        fake.publish(HomeNowPlayingReading(access: .ready))
        #expect(home.track == nil)
        #expect(home.nowPlayingNotice == nil)
        #expect(HomeNowPlayingState.resolve(HomeNowPlayingReading(access: .ready)) == .idle)
    }

    @Test func aPlayerOpenWithNothingLoadedSaysSo() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.publish(HomeNowPlayingReading(access: .ready, track: nil, runningPlayer: spotify))
        #expect(home.track == nil)
        #expect(home.nowPlayingNotice == .playerEmpty(player: "Spotify"))
    }

    @Test func missingPermissionIsACallToActionAndTheClickIsTheOnlyAsk() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.publish(HomeNowPlayingReading(access: .needsAuthorization, track: nil, runningPlayer: spotify))
        #expect(home.nowPlayingNotice == .permission(player: "Spotify", denied: false))
        #expect(fake.authorizations == 0)
        home.nowPlaying.authorize()
        #expect(fake.authorizations == 1)
        fake.publish(HomeNowPlayingReading(access: .denied, track: nil, runningPlayer: spotify))
        #expect(home.nowPlayingNotice == .permission(player: "Spotify", denied: true))
        // Refused or not asked, but no player open: nothing to ask for.
        fake.publish(HomeNowPlayingReading(access: .denied))
        #expect(home.nowPlayingNotice == nil)
    }

    @Test func grantingThePermissionReplacesTheNoticeByTheTrack() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.publish(HomeNowPlayingReading(access: .needsAuthorization, track: nil, runningPlayer: spotify))
        fake.publish(HomeNowPlayingReading(access: .ready, track: track(playing: true), runningPlayer: spotify))
        #expect(home.nowPlayingNotice == nil)
        #expect(home.track?.title == "Reason")
    }

    // MARK: open and closed

    @Test func fastRefreshRunsOnlyWhileTheHomeIsOpen() async {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        let feed = home.nowPlaying
        #expect(fake.openCalls.isEmpty)
        #expect(fake.refreshes == 0)
        feed.setOpen(true)
        feed.setOpen(true)   // same value: nothing again
        #expect(fake.openCalls == [true])
        while fake.refreshes == 0 { await Task.yield() }
        #expect(fake.refreshes == 1, "one immediate read when the home opens")
        feed.setOpen(false)
        #expect(fake.openCalls == [true, false])
        for _ in 0..<50 { await Task.yield() }
        #expect(fake.refreshes == 1, "closed: no further read")
        feed.setOpen(true)
        while fake.refreshes < 2 { await Task.yield() }
        #expect(fake.openCalls == [true, false, true])
    }

    @Test func openingShowsWhatThePlayerIsDoingBeforeTheRefreshReturns() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.reading = HomeNowPlayingReading(access: .ready, track: track(playing: true), runningPlayer: spotify)
        home.nowPlaying.setOpen(true)
        #expect(home.track?.title == "Reason")
    }

    // MARK: transport

    @Test func transportGoesThroughTheSourceAndTheCardFollowsTheNextReading() {
        let fake = FakeNowPlayingSource()
        let (home, cleanup) = home(fake)
        defer { cleanup() }
        fake.publish(HomeNowPlayingReading(access: .ready, track: track(playing: true), runningPlayer: spotify))
        home.transport(.playPause)
        home.transport(.next)
        home.transport(.previous)
        #expect(fake.sent == [.playPause, .next, .previous])
        // The source answers with the paused state after the command: the card updates.
        fake.publish(HomeNowPlayingReading(access: .ready, track: track(playing: false), runningPlayer: spotify))
        #expect(home.track?.isPlaying == false)
    }

    // MARK: independence

    @Test func theFeedNeverReadsTheClosedIslandsActivities() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/ShellKit/Home")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("HomeNowPlayingFeed") || $0.hasPrefix("HomeNowPlayingReading") }
        #expect(files.count == 2)
        for file in files {
            let text = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.contains("ActivityCenter"), "\(file)")
            #expect(!text.contains("ActivityLayout"), "\(file)")
            #expect(!text.contains("import NowPlayingFeature"), "\(file)")
        }
        let delegate = folder.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MacIsland/AppDelegate.swift")
        let app = try String(contentsOf: delegate, encoding: .utf8)
        #expect(!app.contains("musicTrack("), "the card is no longer fed from the music wing")
    }

    @Test func theLiveTrackKeepsEveryFieldTheCardNeeds() {
        let t = track(playing: true)
        #expect(t.album == "Migration")
        #expect(t.position == 40 && t.duration == 100)
        #expect(t.playerBundleID == "com.spotify.client" && t.playerName == "Spotify")
        #expect(t.artworkData == Data([1, 2, 3]))
    }
}
