import AppKit
import Foundation

/// What the Home now-playing card shows. The app feeds it; ShellKit imports no feature module.
public struct HomeTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var artworkData: Data?
    public var isPlaying: Bool
    /// 0...1, nil when unknown.
    public var progress: Double?
    public var album: String
    /// Seconds. Nil when the player does not say (streams, radio).
    public var position: TimeInterval?
    public var duration: TimeInterval?
    /// The player that owns the track (Spotify, Music...), when the feed knows it.
    public var playerBundleID: String?
    public var playerName: String?

    public init(title: String, artist: String = "", artworkData: Data? = nil, isPlaying: Bool = true, progress: Double? = nil,
                album: String = "", position: TimeInterval? = nil, duration: TimeInterval? = nil,
                playerBundleID: String? = nil, playerName: String? = nil) {
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.isPlaying = isPlaying
        self.progress = progress
        self.album = album
        self.position = position
        self.duration = duration
        self.playerBundleID = playerBundleID
        self.playerName = playerName
    }
}

public enum HomeTransport: Sendable {
    case previous, playPause, next
}

/// Posts a system media key (play/pause, next, previous): works for whichever app is playing.
public enum MediaKeyPoster {
    static func keyCode(_ command: HomeTransport) -> Int {
        switch command {
        case .playPause: 16  // NX_KEYTYPE_PLAY
        case .next: 17       // NX_KEYTYPE_NEXT
        case .previous: 18   // NX_KEYTYPE_PREVIOUS
        }
    }

    /// data1 of a system-defined key event: key code in the high word, 0xA down / 0xB up in the flags byte.
    static func data1(key: Int, down: Bool) -> Int {
        (key << 16) | ((down ? 0xA : 0xB) << 8)
    }

    @MainActor
    public static func post(_ command: HomeTransport) {
        let key = keyCode(command)
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, subtype: 8, data1: data1(key: key, down: down), data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
