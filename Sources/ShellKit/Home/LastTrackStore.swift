import Foundation

/// Reads, writes and removes the last-track file. Local only: nothing here touches the network.
public struct LastTrackStore: Sendable {
    public var url: URL?

    public init(url: URL?) { self.url = url }

    /// `~/Library/Application Support/be.roldy.macisland/Data/last-track`, the folder the other private files use.
    public static var live: LastTrackStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return LastTrackStore(url: base?
            .appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("last-track"))
    }

    /// Nil when there is no file, it is too big, or it is corrupt.
    public func load() -> LastTrackRecord? {
        guard let url, let size = fileSize(), size <= LastTrackRecord.maxFileBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return LastTrackRecord.decode(data)
    }

    /// Atomic, owner-only (0600 file, 0700 folder).
    @discardableResult
    public func save(_ record: LastTrackRecord) -> Bool {
        guard let url, let data = record.encoded() else { return false }
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])) != nil,
              (try? data.write(to: url, options: .atomic)) != nil else { return false }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    public func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Modification date, used to skip decoding an unchanged file. Nil when there is no file.
    public func modificationDate() -> Date? {
        guard let url else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func fileSize() -> Int? {
        guard let url else { return nil }
        return ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue
    }
}
