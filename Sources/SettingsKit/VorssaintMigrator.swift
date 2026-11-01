import Foundation

public struct MigrationReport: Equatable {
    public var migratedKeys: [String] = []
    /// Recognised but deliberately not carried over (secrets, bookmarks, out of scope).
    public var skippedKeys: [String] = []
    /// Not recognised: logged, never written, never guessed.
    public var unknownKeys: [String] = []
    public var copiedFiles: [String] = []
    /// Symbolic links found in the source support folder (relative names). Never followed, never copied.
    public var skippedLinks: [String] = []
    public var backupURL: URL?
    public var alreadyDone = false
    public var nothingToMigrate = false

    public init() {}
}

public enum MigrationError: Error, CustomStringConvertible {
    /// A step failed after the backup was written. `backup` and `migratedKeys` say what is already on disk.
    case partial(backup: URL?, migratedKeys: Int, underlying: Error)

    public var description: String {
        switch self {
        case let .partial(backup, keys, underlying):
            return "migration failed after partial write (backup: \(backup?.path ?? "none"), "
                + "\(keys) keys already migrated): \(underlying)"
        }
    }
}

/// First-launch import of a Vorssaint install. Copy only: the source is never modified.
public struct VorssaintMigrator {
    public static let doneKey = "migration.vorssaint.done"

    public let sourceDomain: [String: Any]
    public let sourceSupportDir: URL?
    public let destDefaults: UserDefaults
    public let destSupportDir: URL
    public let now: () -> Date

    public init(
        sourceDomain: [String: Any],
        sourceSupportDir: URL?,
        destDefaults: UserDefaults,
        destSupportDir: URL,
        now: @escaping () -> Date = Date.init
    ) {
        self.sourceDomain = sourceDomain
        self.sourceSupportDir = sourceSupportDir
        self.destDefaults = destDefaults
        self.destSupportDir = destSupportDir
        self.now = now
    }

    /// Data files worth keeping. `agent-prices.json` is not one of them: the new app ships its own table.
    static let dataEntries = ["Scratchpad.json", "ClipboardHistory.json", "ClipboardImages"]

    public func run() throws -> MigrationReport {
        var report = MigrationReport()
        let fm = FileManager.default

        if destDefaults.bool(forKey: Self.doneKey) {
            report.alreadyDone = true
            return report
        }

        let supportExists = sourceSupportDir.map { fm.fileExists(atPath: $0.path) } ?? false
        if sourceDomain.isEmpty && !supportExists {
            report.nothingToMigrate = true
            return report
        }

        // 1. Backup first. If it fails nothing else has been touched.
        report.backupURL = try backup(supportExists: supportExists, links: &report.skippedLinks)

        do {
            // 2. Preferences.
            for key in sourceDomain.keys.sorted() {
                switch VorssaintKeyMap.verdict(for: key) {
                case .skip:
                    report.skippedKeys.append(key)
                case .unknown:
                    report.unknownKeys.append(key)
                case .carry:
                    if destDefaults.object(forKey: key) == nil {
                        destDefaults.set(sourceDomain[key], forKey: key)
                        report.migratedKeys.append(key)
                    }
                }
            }

            // 3. Data files, never over an existing file.
            if let source = sourceSupportDir, supportExists {
                let dataDir = destSupportDir.appendingPathComponent("Data")
                try makePrivateDirectory(dataDir)
                for entry in Self.dataEntries {
                    let from = source.appendingPathComponent(entry)
                    guard fm.fileExists(atPath: from.path) else { continue }
                    try copyTree(from: from, to: dataDir.appendingPathComponent(entry),
                                 relativeName: entry, copied: &report.copiedFiles, links: &report.skippedLinks)
                }
            }
        } catch {
            throw MigrationError.partial(
                backup: report.backupURL, migratedKeys: report.migratedKeys.count, underlying: error)
        }

        destDefaults.set(true, forKey: Self.doneKey)
        return report
    }

    // MARK: - Backup

    func backup(
        supportExists: Bool, links: inout [String], folderPrefix: String = "vorssaint"
    ) throws -> URL {
        try makePrivateDirectory(destSupportDir)
        let backups = destSupportDir.appendingPathComponent("Backups")
        try makePrivateDirectory(backups)
        let dir = backups.appendingPathComponent("\(folderPrefix)-\(Self.stamp(now()))")
        try makePrivateDirectory(dir)

        let plist = try PropertyListSerialization.data(
            fromPropertyList: sourceDomain, format: .xml, options: 0)
        let prefs = dir.appendingPathComponent("preferences.plist")
        try plist.write(to: prefs, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: prefs.path)

        if let source = sourceSupportDir, supportExists {
            var ignored: [String] = []
            try copyTree(from: source, to: dir.appendingPathComponent("support"),
                         relativeName: "", copied: &ignored, links: &links, overwrite: true, isRoot: true)
        }
        return dir
    }

    // MARK: - File helpers

    func makePrivateDirectory(_ url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.createDirectory(
            at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    /// Recursive copy: directories 0700, files 0600. Skips a destination that exists unless `overwrite`.
    /// Symbolic links are never followed or copied; they are listed in `links` (once per name).
    private func copyTree(
        from: URL, to: URL, relativeName: String, copied: inout [String], links: inout [String],
        overwrite: Bool = false, isRoot: Bool = false
    ) throws {
        let fm = FileManager.default
        if !isRoot, (try? from.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            if !links.contains(relativeName) { links.append(relativeName) }
            return
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: from.path, isDirectory: &isDir) else { return }

        if isDir.boolValue {
            try makePrivateDirectory(to)
            for child in try fm.contentsOfDirectory(atPath: from.path).sorted() {
                let name = relativeName.isEmpty ? child : "\(relativeName)/\(child)"
                try copyTree(from: from.appendingPathComponent(child),
                             to: to.appendingPathComponent(child),
                             relativeName: name, copied: &copied, links: &links, overwrite: overwrite)
            }
            return
        }

        if fm.fileExists(atPath: to.path) {
            guard overwrite else { return }
            try fm.removeItem(at: to)
        }
        try fm.copyItem(at: from, to: to)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: to.path)
        copied.append(relativeName)
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
