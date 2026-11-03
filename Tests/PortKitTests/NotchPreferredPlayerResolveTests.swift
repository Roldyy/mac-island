import Foundation
import Testing
@testable import PortKit

/// The ported island's player resolution shares the Mac Island resolver: the Music blocker and a chosen Spotify
/// keep Apple Music from opening.
@Suite struct NotchPreferredPlayerResolveTests {
    private let both: Set<String> = ["com.spotify.client", "com.apple.Music"]

    @Test func chosenSpotifyBeatsAStaleMusicTrack() {
        #expect(NotchPreferredPlayer.resolve(choice: "com.spotify.client", lastPlayed: "com.apple.Music") { both.contains($0) }
                == "com.spotify.client")
    }

    @Test func theBlockerNeverReturnsMusic() {
        #expect(NotchPreferredPlayer.resolve(choice: "", lastPlayed: "com.apple.Music", blockerOn: true) { both.contains($0) }
                == "com.spotify.client")
        #expect(NotchPreferredPlayer.resolve(choice: "com.apple.Music", lastPlayed: nil, blockerOn: true) { $0 == "com.apple.Music" } == nil)
    }

    @Test func withoutTheBlockerAChosenMusicStillOpens() {
        #expect(NotchPreferredPlayer.resolve(choice: "com.apple.Music", lastPlayed: nil) { both.contains($0) } == "com.apple.Music")
    }
}
