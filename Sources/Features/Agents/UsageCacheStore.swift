import Foundation

/// Where the parse cache lives on disk: `Application Support/be.roldy.macisland/usage-cache-v1.bin`,
/// owner-only (0600). The file holds token counts, model ids, folder names and message ids, never message text.
struct UsageCacheStore: Sendable {
    var url: URL

    init(url: URL) { self.url = url }

    static var `default`: UsageCacheStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return UsageCacheStore(url: support.appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("usage-cache-v\(UsageCacheCodec.version).bin"))
    }

    /// nil for a missing file and for one that is corrupt, truncated or from another schema (it is
    /// ignored and replaced by the next `write`).
    func read() -> [String: UsageFileCache.Entry]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? UsageCacheCodec.decode(data)
    }

    /// Atomic: a temp file in the same folder (created 0600) is renamed over the old one, so a crash
    /// mid-write never leaves a half cache. Failures are swallowed by design: a cache that cannot be
    /// saved only costs one slow launch.
    @discardableResult
    func write(_ entries: [String: UsageFileCache.Entry], keepingSince: Date?) -> Bool {
        let data = UsageCacheCodec.encode(entries, keepingSince: keepingSince)
        let folder = url.deletingLastPathComponent()
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let temp = folder.appendingPathComponent(".usage-cache-\(UUID().uuidString).tmp")
            guard manager.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                return false
            }
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temp)
            } else {
                try manager.moveItem(at: temp, to: url)
            }
            return true
        } catch {
            return false
        }
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}
