import Foundation

enum BundleIDs {
    static let spotify = "com.spotify.client"
    static let music = "com.apple.Music"
}

/// One reading of "what a source is playing". Plain value, safe to pass across actors.
struct NowPlayingSnapshot: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var artworkData: Data?
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var sourceBundleID: String

    init(title: String, artist: String, album: String, artworkURL: URL?, artworkData: Data?,
                isPlaying: Bool, position: TimeInterval, duration: TimeInterval, sourceBundleID: String) {
        self.title = title; self.artist = artist; self.album = album
        self.artworkURL = artworkURL; self.artworkData = artworkData
        self.isPlaying = isPlaying; self.position = position; self.duration = duration
        self.sourceBundleID = sourceBundleID
    }

    /// Stable identity of the track, used as artwork cache key.
    var trackKey: String { "\(sourceBundleID)|\(title)|\(artist)|\(album)" }

    /// 0...1, nil when the duration is unknown (streams, radio).
    var progress: Double? {
        guard duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }
}
