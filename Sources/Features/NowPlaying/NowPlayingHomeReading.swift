import Foundation

/// What the island home needs from this feature, as plain public values (the app maps them to ShellKit's own
/// types: ShellKit imports no feature module).
public struct NowPlayingHomeTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var artworkData: Data?
    public var isPlaying: Bool
    public var position: TimeInterval
    public var duration: TimeInterval
    public var playerBundleID: String
    public var playerName: String
}

public struct NowPlayingHomePlayer: Equatable, Sendable {
    public var bundleID: String
    public var name: String
}

public enum NowPlayingHomeAccess: Equatable, Sendable { case needsAuthorization, ready, denied }

public enum NowPlayingHomeCommand: Sendable { case previous, playPause, next }

public struct NowPlayingHomeReading: Equatable, Sendable {
    public var access: NowPlayingHomeAccess
    public var track: NowPlayingHomeTrack?
    public var runningPlayer: NowPlayingHomePlayer?
    /// Why a player that is open has no track, in one short French line with the AppleScript error number
    /// ("Spotify : autorisation refusée (-1743)"). Nil when nothing went wrong, and always nil with a track.
    public var diagnostic: String?

    public init(access: NowPlayingHomeAccess, track: NowPlayingHomeTrack?, runningPlayer: NowPlayingHomePlayer?,
                diagnostic: String? = nil) {
        self.access = access
        self.track = track
        self.runningPlayer = runningPlayer
        self.diagnostic = diagnostic
    }
}

enum PlayerNames {
    static func name(for bundleID: String) -> String {
        switch bundleID {
        case BundleIDs.spotify: "Spotify"
        case BundleIDs.music: "Musique"
        default: bundleID
        }
    }
}

extension NowPlayingModel {
    /// Pure view of the model for the Home card.
    func homeReading() -> NowPlayingHomeReading {
        let access: NowPlayingHomeAccess = switch self.access {
        case .needsAuthorization: .needsAuthorization
        case .ready: .ready
        case .denied: .denied
        }
        let track = snapshot.map { s in
            NowPlayingHomeTrack(
                title: s.title, artist: s.artist, album: s.album, artworkData: artwork ?? s.artworkData,
                isPlaying: s.isPlaying, position: s.position, duration: s.duration,
                playerBundleID: s.sourceBundleID, playerName: PlayerNames.name(for: s.sourceBundleID))
        }
        let player = runningPlayerBundleID.map { NowPlayingHomePlayer(bundleID: $0, name: PlayerNames.name(for: $0)) }
        // Only a player that is open and unreadable has something to explain.
        let diagnostic = track == nil && player != nil ? fault?.line : nil
        return NowPlayingHomeReading(access: access, track: track, runningPlayer: player, diagnostic: diagnostic)
    }
}
