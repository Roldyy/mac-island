import Foundation
import SettingsKit

public enum SettingsBackupError: Error, Equatable {
    case notASettingsFile
}

/// Saves and restores the app's preferences as property lists in the migrator's `Backups` folder.
public struct SettingsBackup {
    public static let filePrefix = "settings-"

    let defaults: UserDefaults
    let domain: String
    public let directory: URL
    let now: () -> Date

    /// `Application Support/be.roldy.macisland/Backups`, the folder the Vorssaint migrator already uses.
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("be.roldy.macisland").appendingPathComponent("Backups")
    }

    public init(defaults: UserDefaults, domain: String, directory: URL = SettingsBackup.defaultDirectory(),
                now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.domain = domain
        self.directory = directory
        self.now = now
    }

    /// System keys that belong to macOS, not to the app.
    static func isSystemKey(_ key: String) -> Bool {
        key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("com.apple.") || key.hasPrefix("SU")
    }

    /// What a backup neither exports nor restores: system keys, and this Mac's runtime markers, consents,
    /// evidence and journals (`SettingsMachineState`, the one list the v2 import and its purge share).
    static func isLeftOut(_ key: String) -> Bool {
        isSystemKey(key) || SettingsMachineState.isExcluded(key)
    }

    func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now())
    }

    @discardableResult
    public func export() throws -> URL {
        let kept = (defaults.persistentDomain(forName: domain) ?? [:]).filter { !Self.isLeftOut($0.key) }
        let data = try PropertyListSerialization.data(fromPropertyList: kept, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("\(Self.filePrefix)\(stamp()).plist")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Newest first.
    public func list() -> [URL] { Self.list(in: directory) }

    /// Directory listing only, so a page can run it off the main thread without capturing `UserDefaults`.
    public static func list(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(Self.filePrefix) && $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Writes every preference of the file back. Keys the file does not hold stay as they are, and so do the keys
    /// of `SettingsMachineState` whatever the file says (an older backup may still carry them): a live marker is
    /// neither overwritten nor deleted, a consent is never brought back without a click.
    public func restore(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw SettingsBackupError.notASettingsFile
        }
        for (key, value) in dict where !Self.isLeftOut(key) { defaults.set(value, forKey: key) }
    }
}
