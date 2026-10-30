import Foundation

public enum BundleIDs {
    public static let spotify = "com.spotify.client"
    public static let music = "com.apple.Music"
}

/// One reading of "what a source is playing". Plain value, safe to pass across actors.
public struct NowPlayingSnapshot: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var artworkData: Data?
    public var isPlaying: Bool
    public var position: TimeInterval
    public var duration: TimeInterval
    public var sourceBundleID: String

    public init(title: String, artist: String, album: String, artworkURL: URL?, artworkData: Data?,
                isPlaying: Bool, position: TimeInterval, duration: TimeInterval, sourceBundleID: String) {
        self.title = title; self.artist = artist; self.album = album
        self.artworkURL = artworkURL; self.artworkData = artworkData
        self.isPlaying = isPlaying; self.position = position; self.duration = duration
        self.sourceBundleID = sourceBundleID
    }

    /// Stable identity of the track, used as artwork cache key.
    public var trackKey: String { "\(sourceBundleID)|\(title)|\(artist)|\(album)" }

    /// 0...1, nil when the duration is unknown (streams, radio).
    public var progress: Double? {
        guard duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }
}
