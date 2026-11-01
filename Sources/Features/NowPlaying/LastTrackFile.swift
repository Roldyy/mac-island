import Foundation

/// What is kept of the last track. Same JSON as ShellKit's `LastTrackRecord`, which reads it (ShellKit cannot be
/// imported here): `{version, title, artist, album, playerBundleID, timestamp (seconds since 1970), artwork (base64 JPEG)}`.
/// Each side has a test on the same literal.
struct StoredTrack: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maxFileBytes = 512 * 1024
    static let maxTextLength = 300

    var version = StoredTrack.currentVersion
    var title: String
    var artist: String
    var album: String
    var playerBundleID: String
    var timestamp: Date
    var artwork: Data?

    init(title: String, artist: String, album: String, playerBundleID: String, timestamp: Date, artwork: Data?) {
        self.title = String(title.prefix(Self.maxTextLength))
        self.artist = String(artist.prefix(Self.maxTextLength))
        self.album = String(album.prefix(Self.maxTextLength))
        self.playerBundleID = String(playerBundleID.prefix(Self.maxTextLength))
        self.timestamp = timestamp
        self.artwork = artwork
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self), data.count <= Self.maxFileBytes else { return nil }
        return data
    }

    /// Nil for anything that is not a well-formed record of this version.
    static func decode(_ data: Data) -> StoredTrack? {
        guard data.count <= maxFileBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let stored = try? decoder.decode(StoredTrack.self, from: data), stored.version == currentVersion,
              !stored.title.isEmpty, !stored.playerBundleID.isEmpty else { return nil }
        return stored
    }
}

/// The file itself: Application Support/be.roldy.macisland/Data/last-track, 0600, atomic. Local only.
protocol LastTrackFile: Sendable {
    func write(_ track: StoredTrack)
    func read() -> StoredTrack?
    func clear()
}

struct DiskLastTrackFile: LastTrackFile {
    let url: URL?

    init(url: URL? = DiskLastTrackFile.liveURL) { self.url = url }

    static var liveURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("last-track")
    }

    func write(_ track: StoredTrack) {
        guard let url, let data = track.encoded() else { return }
        let manager = FileManager.default
        guard (try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])) != nil,
              (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func read() -> StoredTrack? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return StoredTrack.decode(data)
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
