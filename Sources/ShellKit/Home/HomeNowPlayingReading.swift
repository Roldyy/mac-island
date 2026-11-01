import Foundation

/// One reading of the music players, as plain data. The app builds it from the Now Playing feature;
/// ShellKit never imports that feature and never reads the closed island's activities.
public struct HomeNowPlayingReading: Equatable, Sendable {
    /// Can the app talk to the players (macOS Automation permission)?
    public enum Access: Equatable, Sendable { case needsAuthorization, ready, denied }

    /// A player that is open right now.
    public struct Player: Equatable, Sendable {
        public var bundleID: String
        public var name: String

        public init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    public var access: Access
    /// The live track, playing or paused. Nil when nothing is loaded or access is missing.
    public var track: HomeTrack?
    /// The first known player that is open, whatever it plays.
    public var runningPlayer: Player?

    public init(access: Access, track: HomeTrack? = nil, runningPlayer: Player? = nil) {
        self.access = access
        self.track = track
        self.runningPlayer = runningPlayer
    }

    /// No feature behind the feed: the card falls back to the stored last track.
    public static let none = HomeNowPlayingReading(access: .needsAuthorization)
}

/// Why the card has no track to show although a player is open.
public enum HomeNowPlayingNotice: Equatable, Sendable {
    /// Spotify (or Music) is open but the Automation permission is missing; `denied` once the user refused it.
    case permission(player: String, denied: Bool)
    /// The player is open and has nothing loaded.
    case playerEmpty(player: String)
}

/// What the card shows: a live track, a notice, or neither (then the stored last track).
public struct HomeNowPlayingState: Equatable, Sendable {
    public var track: HomeTrack?
    public var notice: HomeNowPlayingNotice?

    public init(track: HomeTrack? = nil, notice: HomeNowPlayingNotice? = nil) {
        self.track = track
        self.notice = notice
    }

    public static let idle = HomeNowPlayingState()

    /// Pure: states of the card from a reading.
    /// - playing or paused: the live track (a paused one is NOT replaced by the stored last track);
    /// - a player open with nothing loaded: a notice;
    /// - a player open and no permission: the call to action;
    /// - no player: idle (the stored last track).
    public static func resolve(_ reading: HomeNowPlayingReading) -> HomeNowPlayingState {
        switch reading.access {
        case .ready:
            if let track = reading.track { return HomeNowPlayingState(track: track) }
            if let player = reading.runningPlayer { return HomeNowPlayingState(notice: .playerEmpty(player: player.name)) }
            return .idle
        case .needsAuthorization, .denied:
            guard let player = reading.runningPlayer else { return .idle }
            return HomeNowPlayingState(notice: .permission(player: player.name, denied: reading.access == .denied))
        }
    }
}
