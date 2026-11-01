import Foundation

/// The last track that played, kept on this Mac only so the idle home card can show it and reopen its player.
///
/// File contract (also written by `NowPlayingFeature`, which ShellKit cannot import): one JSON object
/// `{version, title, artist, album, playerBundleID, timestamp (seconds since 1970), artwork (base64 JPEG, optional)}`.
/// Both sides keep a test on the same literal, so a drift of either one fails.
public struct LastTrackRecord: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// A bigger file is treated as corrupt and ignored (a 256 px JPEG is far below this).
    public static let maxFileBytes = 512 * 1024
    public static let maxTextLength = 300

    public var version: Int
    public var title: String
    public var artist: String
    public var album: String
    /// The app that played it: `com.spotify.client`, `com.apple.Music` or any other player.
    public var playerBundleID: String
    /// When the track stopped playing (or started, until it stops).
    public var timestamp: Date
    public var artworkJPEG: Data?

    enum CodingKeys: String, CodingKey {
        case version, title, artist, album, playerBundleID, timestamp
        case artworkJPEG = "artwork"
    }

    public init(title: String, artist: String = "", album: String = "", playerBundleID: String,
                timestamp: Date, artworkJPEG: Data? = nil) {
        version = Self.currentVersion
        self.title = Self.clipped(title)
        self.artist = Self.clipped(artist)
        self.album = Self.clipped(album)
        self.playerBundleID = Self.clipped(playerBundleID)
        self.timestamp = timestamp
        self.artworkJPEG = artworkJPEG
    }

    static func clipped(_ text: String) -> String { String(text.prefix(maxTextLength)) }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self), data.count <= Self.maxFileBytes else { return nil }
        return data
    }

    /// Nil for anything that is not a well-formed record of this version: corruption never reaches the UI.
    public static func decode(_ data: Data) -> LastTrackRecord? {
        guard data.count <= maxFileBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let record = try? decoder.decode(LastTrackRecord.self, from: data),
              record.version == currentVersion,
              !record.title.isEmpty, !record.playerBundleID.isEmpty,
              record.timestamp.timeIntervalSince1970.isFinite else { return nil }
        return record
    }
}
