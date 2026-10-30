import Foundation
import Testing
@testable import SettingsKit

/// All fixtures are synthetic. Never put a real export of a user's defaults here.
private struct Bench {
    let root: URL
    let sourceSupport: URL
    let destSupport: URL
    let defaults: UserDefaults
    private let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-tests-\(UUID().uuidString)")
        sourceSupport = root.appendingPathComponent("src-support")
        destSupport = root.appendingPathComponent("dest-support")
        try FileManager.default.createDirectory(
            at: sourceSupport.appendingPathComponent("ClipboardImages"),
            withIntermediateDirectories: true)
        suite = "mis-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func write(_ text: String, to relative: String) throws {
        try text.write(
            to: sourceSupport.appendingPathComponent(relative), atomically: true, encoding: .utf8)
    }

    func migrator(_ domain: [String: Any], support: URL? = nil, date: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> VorssaintMigrator {
        VorssaintMigrator(
            sourceDomain: domain, sourceSupportDir: support ?? sourceSupport,
            destDefaults: defaults, destSupportDir: destSupport, now: { date })
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private func permissions(_ url: URL) -> Int {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs?[.posixPermissions] as? Int) ?? -1
}

@Suite struct VorssaintMigratorTests {
    @Test func carriesKnownKeysWithTheirValues() throws {
        let b = try Bench(); defer { b.cleanup() }
        let layout = Data("{\"version\":1}".utf8)
        let report = try b.migrator([
            "notchSize": "spacious",
            "notchIdleContent": "agents",
            "notchQuickAccessLayout": layout,
            "clipboardHistoryLimit": 50,
            "keepAwakeMouseJiggleEnabled": true,
            "pastePlainShortcut": "option+command:9",
        ]).run()

        #expect(b.defaults.string(forKey: "notchSize") == "spacious")
        #expect(b.defaults.string(forKey: "notchIdleContent") == "agents")
        #expect(b.defaults.data(forKey: "notchQuickAccessLayout") == layout)
        #expect(b.defaults.integer(forKey: "clipboardHistoryLimit") == 50)
        #expect(b.defaults.bool(forKey: "keepAwakeMouseJiggleEnabled") == true)
        #expect(b.defaults.string(forKey: "pastePlainShortcut") == "option+command:9")
        #expect(report.migratedKeys.count == 6)
    }

    @Test func skipsSecretsBookmarksAndFlagsOfTheOldApp() throws {
        let b = try Bench(); defer { b.cleanup() }
        let report = try b.migrator([
            "commandBarQueryHabitKey": "secret-looking-value",
            "notchDownloadsFolderBookmark": Data([1, 2, 3]),
            "featureAvailable.mixer": true,
            "featureHubKeptFeatures": "superKey",
            "fanControlHelperVersion": "9",
            "notchSize": "compact",
        ]).run()

        for key in ["commandBarQueryHabitKey", "notchDownloadsFolderBookmark",
                    "featureAvailable.mixer", "featureHubKeptFeatures", "fanControlHelperVersion"] {
            #expect(b.defaults.object(forKey: key) == nil, "\(key) must not be carried")
            #expect(report.skippedKeys.contains(key))
        }
        #expect(b.defaults.string(forKey: "notchSize") == "compact")
    }

    @Test func unknownKeysAreReportedNeverWritten() throws {
        let b = try Bench(); defer { b.cleanup() }
        let report = try b.migrator(["someFutureThing": 1, "notchSize": "compact"]).run()
        #expect(report.unknownKeys == ["someFutureThing"])
        #expect(b.defaults.object(forKey: "someFutureThing") == nil)
    }

    @Test func backupIsWrittenWithRestrictedPermissionsAndKeepsEverything() throws {
        let b = try Bench(); defer { b.cleanup() }
        try b.write("{\"pads\":[]}", to: "Scratchpad.json")
        let report = try b.migrator(["notchSize": "compact", "commandBarQueryHabitKey": "x"]).run()

        let backup = try #require(report.backupURL)
        #expect(backup.path.hasPrefix(b.destSupport.appendingPathComponent("Backups").path))
        #expect(permissions(backup) == 0o700)

        let prefs = backup.appendingPathComponent("preferences.plist")
        #expect(permissions(prefs) == 0o600)
        let data = try Data(contentsOf: prefs)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["commandBarQueryHabitKey"] as? String == "x", "the backup is complete, even for skipped keys")

        let pad = backup.appendingPathComponent("support/Scratchpad.json")
        #expect(FileManager.default.fileExists(atPath: pad.path))
        #expect(permissions(pad) == 0o600)
    }

    @Test func copiesDataFilesButNotThePriceTable() throws {
        let b = try Bench(); defer { b.cleanup() }
        try b.write("{\"pads\":[]}", to: "Scratchpad.json")
        try b.write("[]", to: "ClipboardHistory.json")
        try b.write("{}", to: "agent-prices.json")
        try b.write("png", to: "ClipboardImages/1.png")
        let report = try b.migrator(["notchSize": "compact"]).run()

        let data = b.destSupport.appendingPathComponent("Data")
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("Scratchpad.json").path))
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("ClipboardHistory.json").path))
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("ClipboardImages/1.png").path))
        #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("agent-prices.json").path))
        #expect(permissions(data.appendingPathComponent("ClipboardHistory.json")) == 0o600)
        #expect(report.copiedFiles.contains("ClipboardHistory.json"))
    }

    @Test func sourceIsNeverModified() throws {
        let b = try Bench(); defer { b.cleanup() }
        try b.write("original", to: "Scratchpad.json")
        _ = try b.migrator(["notchSize": "compact"]).run()
        let text = try String(contentsOf: b.sourceSupport.appendingPathComponent("Scratchpad.json"), encoding: .utf8)
        #expect(text == "original")
    }

    @Test func secondRunIsANoOpAndKeepsLaterChanges() throws {
        let b = try Bench(); defer { b.cleanup() }
        let domain: [String: Any] = ["notchSize": "spacious"]
        _ = try b.migrator(domain).run()
        b.defaults.set("compact", forKey: "notchSize")

        let second = try b.migrator(domain).run()
        #expect(second.alreadyDone)
        #expect(b.defaults.string(forKey: "notchSize") == "compact")
        let backups = try FileManager.default.contentsOfDirectory(
            atPath: b.destSupport.appendingPathComponent("Backups").path)
        #expect(backups.count == 1, "no second backup")
    }

    @Test func neverOverwritesAValueAlreadySetInTheNewApp() throws {
        let b = try Bench(); defer { b.cleanup() }
        b.defaults.set("compact", forKey: "notchSize")
        let report = try b.migrator(["notchSize": "spacious", "notchIdleContent": "agents"]).run()
        #expect(b.defaults.string(forKey: "notchSize") == "compact")
        #expect(b.defaults.string(forKey: "notchIdleContent") == "agents")
        #expect(report.migratedKeys == ["notchIdleContent"])
    }

    @Test func nothingToMigrateDoesNotMarkItDone() throws {
        let b = try Bench(); defer { b.cleanup() }
        let missing = b.root.appendingPathComponent("does-not-exist")
        let report = try b.migrator([:], support: missing).run()
        #expect(report.nothingToMigrate)
        #expect(b.defaults.bool(forKey: VorssaintMigrator.doneKey) == false)
        #expect(!FileManager.default.fileExists(atPath: b.destSupport.appendingPathComponent("Backups").path))
    }

    @Test func aFailedBackupAbortsBeforeAnyKeyIsWritten() throws {
        let b = try Bench(); defer { b.cleanup() }
        // A plain file where the Backups directory must go makes the backup impossible.
        try FileManager.default.createDirectory(at: b.destSupport, withIntermediateDirectories: true)
        try "block".write(to: b.destSupport.appendingPathComponent("Backups"), atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) { try b.migrator(["notchSize": "compact"]).run() }
        #expect(b.defaults.object(forKey: "notchSize") == nil)
        #expect(b.defaults.bool(forKey: VorssaintMigrator.doneKey) == false)
    }

    @Test func directorySymlinkIsNeitherFollowedNorCopiedAndIsListed() throws {
        let b = try Bench(); defer { b.cleanup() }
        let outside = b.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "secret".write(to: outside.appendingPathComponent("leak.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: b.sourceSupport.appendingPathComponent("ClipboardImages/linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: b.sourceSupport.appendingPathComponent("Scratchpad.json"),
            withDestinationURL: outside.appendingPathComponent("leak.txt"))
        try b.write("img", to: "ClipboardImages/a.png")
        let originalMode = permissions(outside)

        let report = try b.migrator(["notchSize": "compact"]).run()

        #expect(report.skippedLinks.sorted() == ["ClipboardImages/linked", "Scratchpad.json"])
        #expect(report.copiedFiles.contains("ClipboardImages/a.png"))
        #expect(!report.copiedFiles.contains { $0.contains("leak") || $0.contains("linked") })
        let fm = FileManager.default
        let data = b.destSupport.appendingPathComponent("Data")
        #expect(!fm.fileExists(atPath: data.appendingPathComponent("ClipboardImages/linked").path))
        #expect(!fm.fileExists(atPath: data.appendingPathComponent("Scratchpad.json").path))
        let backupSupport = try #require(report.backupURL).appendingPathComponent("support")
        #expect(!fm.fileExists(atPath: backupSupport.appendingPathComponent("ClipboardImages/linked").path))
        #expect(permissions(outside) == originalMode)
        #expect(permissions(try #require(report.backupURL)) == 0o700)
    }

    @Test func failureAfterBackupReportsWhatWasWritten() throws {
        let b = try Bench(); defer { b.cleanup() }
        try b.write("{}", to: "Scratchpad.json")
        // A plain file where the Data directory must go: backup succeeds, the data step fails.
        try FileManager.default.createDirectory(at: b.destSupport, withIntermediateDirectories: true)
        try "block".write(to: b.destSupport.appendingPathComponent("Data"), atomically: true, encoding: .utf8)

        do {
            _ = try b.migrator(["notchSize": "compact", "clipboardHistoryLimit": 50]).run()
            Issue.record("expected a throw")
        } catch let MigrationError.partial(backup, keys, _) {
            let url = try #require(backup)
            #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("preferences.plist").path))
            #expect(keys == 2)
        }
        #expect(b.defaults.bool(forKey: VorssaintMigrator.doneKey) == false)
    }
}
