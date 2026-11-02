import IslandKit
import Testing
@testable import NowPlayingFeature

/// The registry's stopper for Now Playing (it had none: its switch took effect at the next launch).
@Suite(.serialized) struct NowPlayingStopTests {
    @Test @MainActor func stopWithdrawsTheMusicActivityAndTheHomeGoesQuiet() {
        let center = ActivityCenter()
        NowPlayingFeature.start(center: center)
        defer { NowPlayingFeature.stop() }
        #expect(NowPlayingFeature.isStarted)
        let snap = NowPlayingSnapshot(title: "Hollow Years", artist: "A", album: "Al", artworkURL: nil, artworkData: nil,
                                      isPlaying: true, position: 10, duration: 100, sourceBundleID: "com.apple.Music")
        NowPlayingFeature.model.onSnapshot?(snap)
        #expect(center.layout.trailing?.text == "Hollow Years", "started: the track reaches the closed island")

        NowPlayingFeature.stop()

        #expect(!NowPlayingFeature.isStarted)
        #expect(center.layout.isEmpty, "stopped: the music wing is withdrawn at once")
        #expect(NowPlayingFeature.model.onSnapshot == nil, "and a late reading posts nothing")
        NowPlayingFeature.stop()  // idempotent
    }
}
