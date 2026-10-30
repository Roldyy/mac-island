import Foundation
import Testing
@testable import NowPlayingFeature

@Suite struct ParserTests {
    private let sep = "\u{1F}"

    @Test func spotifyPlaying() throws {
        let raw = ["playing", "Song", "Artist", "Album", "12.5", "200000", "https://i.scdn.co/x"].joined(separator: sep)
        let s = try #require(try PlayerScriptParser.parse(raw, bundleID: BundleIDs.spotify, durationUnit: .milliseconds))
        #expect(s.isPlaying && s.title == "Song" && s.artist == "Artist" && s.album == "Album")
        #expect(s.position == 12.5 && s.duration == 200)
        #expect(s.artworkURL == URL(string: "https://i.scdn.co/x"))
        #expect(s.sourceBundleID == BundleIDs.spotify)
    }

    @Test func commaDecimalAndPaused() throws {
        let raw = ["paused", "S", "A", "B", "12,5", "180,25", "missing value"].joined(separator: sep)
        let s = try #require(try PlayerScriptParser.parse(raw, bundleID: BundleIDs.music, durationUnit: .seconds))
        #expect(!s.isPlaying && s.position == 12.5 && s.duration == 180.25 && s.artworkURL == nil)
    }

    @Test func stoppedAndNoneGiveNil() throws {
        #expect(try PlayerScriptParser.parse("stopped", bundleID: "x", durationUnit: .seconds) == nil)
        #expect(try PlayerScriptParser.parse("none\n", bundleID: "x", durationUnit: .seconds) == nil)
    }

    @Test func emptyFieldsKeptInPlace() throws {
        let raw = ["playing", "T", "", "", "0", "0", ""].joined(separator: sep)
        let s = try #require(try PlayerScriptParser.parse(raw, bundleID: "x", durationUnit: .seconds))
        #expect(s.artist == "" && s.album == "" && s.duration == 0)
    }

    @Test func malformedThrows() {
        #expect(throws: NowPlayingError.self) {
            try PlayerScriptParser.parse("playing\(sep)only", bundleID: "x", durationUnit: .seconds)
        }
    }

    @Test func progressClamped() {
        #expect(snap("a", playing: true, position: 150, duration: 100).progress == 1)
        #expect(snap("a", playing: true, position: 5, duration: 0).progress == nil)
    }

    @Test func errorCodeMapping() {
        #expect(NowPlayingError.from(scriptErrorCode: -1743) == .permissionDenied)
        #expect(NowPlayingError.from(scriptErrorCode: -1728) == .noCurrentTrack)
        #expect(NowPlayingError.from(scriptErrorCode: -600) == .scriptFailed(code: -600))
    }

    @Test func everyScriptIsGuardedByAnIsRunningCheck() {
        for id in [BundleIDs.spotify, BundleIDs.music] {
            let guardLine = "if application id \"\(id)\" is running then"
            let scripts = [
                PlayerScripts.status(bundleID: id),
                PlayerScripts.artworkData(bundleID: id),
                PlayerScripts.command(.playPause, bundleID: id),
                PlayerScripts.command(.next, bundleID: id),
                PlayerScripts.command(.previous, bundleID: id),
            ]
            for script in scripts {
                #expect(script.hasPrefix(guardLine), "unguarded: \(script)")
                #expect(script.hasSuffix("end if"))
                // no `tell application id` may sit outside the guard
                let outside = script.components(separatedBy: guardLine)[0]
                #expect(!outside.contains("tell application"))
            }
        }
    }

    @Test func commandScripts() {
        let play = PlayerScripts.command(.playPause, bundleID: BundleIDs.spotify)
        #expect(play.contains("tell application id \"com.spotify.client\" to playpause"))
        #expect(PlayerScripts.command(.next, bundleID: BundleIDs.music)
                .contains("tell application id \"com.apple.Music\" to next track"))
        #expect(PlayerScripts.command(.previous, bundleID: BundleIDs.music)
                .contains("tell application id \"com.apple.Music\" to previous track"))
    }

    @Test func notRunningStatusParsesToNothing() throws {
        let script = PlayerScripts.status(bundleID: BundleIDs.spotify)
        #expect(script.contains("else\n    return \"none\"\nend if"))
        #expect(try PlayerScriptParser.parse("none", bundleID: BundleIDs.spotify, durationUnit: .milliseconds) == nil)
    }
}
