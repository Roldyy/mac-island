import Foundation
import Testing
@testable import SettingsKit

/// Synthetic fixtures only. The destination is a throwaway suite inside a temp folder: no real
/// preference domain is read or written. (SettingsKitTests does not depend on IslandTestSupport,
/// so it keeps the same per-test suite as VorssaintMigratorTests.)
private struct BenchV2 {
    let root: URL
    let destSupport: URL
    let defaults: UserDefaults
    private let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-tests-v2-\(UUID().uuidString)")
        destSupport = root.appendingPathComponent("dest-support")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = root.appendingPathComponent("prefs").path
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func migrator(_ domain: [String: Any]) -> VorssaintMigrator {
        VorssaintMigrator(
            sourceDomain: domain, sourceSupportDir: nil,
            destDefaults: defaults, destSupportDir: destSupport,
            now: { Date(timeIntervalSince1970: 1_790_000_000) })
    }

    func backups() -> [String] {
        (try? FileManager.default.contentsOfDirectory(
            atPath: destSupport.appendingPathComponent("Backups").path)) ?? []
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite struct VorssaintMigratorV2Tests {
    @Test func knownKeyTableHasTheExpectedSize() {
        #expect(VorssaintKnownKeys.all.count == 849)
        #expect(VorssaintKnownKeys.kinds.keys.allSatisfy { VorssaintKnownKeys.all.contains($0) })
    }

    @Test func carriesAKnownKeyAbsentFromTheApp() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        let report = try b.migrator(["batteryLimitPercent": 25, "keepAwakeAutoStart": true]).runV2()
        #expect(b.defaults.integer(forKey: "batteryLimitPercent") == 25)
        #expect(b.defaults.bool(forKey: "keepAwakeAutoStart"))
        #expect(report.carriedKeys == ["batteryLimitPercent", "keepAwakeAutoStart"])
        #expect(b.defaults.bool(forKey: VorssaintMigrator.doneKeyV2))
    }

    @Test func neverOverwritesAKeyTheAppAlreadyHolds() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        b.defaults.set(10, forKey: "batteryLimitPercent")
        let report = try b.migrator(["batteryLimitPercent": 25, "keepAwakeAutoStart": true]).runV2()
        #expect(b.defaults.integer(forKey: "batteryLimitPercent") == 10)
        #expect(report.alreadyPresentKeys == ["batteryLimitPercent"])
        #expect(report.carriedKeys == ["keepAwakeAutoStart"])
    }

    @Test func aValueOfTheWrongTypeIsSkippedAndCounted() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        let report = try b.migrator([
            "batteryLimitPercent": "not a number",  // registered as an integer
            "keepAwakeAutoStart": 1,                // registered as a Bool: 1 is not a Boolean
            "keepAwakeShortcut": "control+option+command:40",
        ]).runV2()
        #expect(b.defaults.object(forKey: "batteryLimitPercent") == nil)
        #expect(b.defaults.object(forKey: "keepAwakeAutoStart") == nil)
        #expect(report.typeMismatchKeys == ["batteryLimitPercent", "keepAwakeAutoStart"])
        #expect(report.carriedKeys == ["keepAwakeShortcut"])
    }

    @Test func featureAvailableBecomesShellEnabledOnlyWhenAbsent() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        b.defaults.set(false, forKey: "shell.enabled.mixer")
        let report = try b.migrator([
            "featureAvailable.mixer": true,
            "featureAvailable.switcher": true,
            "featureAvailable.cleaner": false,
            "featureAvailable.bad": "yes",
            "featureAvailable.": true,
        ]).runV2()
        #expect(b.defaults.bool(forKey: "shell.enabled.mixer") == false, "the app's own switch wins")
        #expect(b.defaults.object(forKey: "shell.enabled.switcher") as? Bool == true)
        #expect(b.defaults.object(forKey: "shell.enabled.cleaner") as? Bool == false)
        #expect(b.defaults.object(forKey: "featureAvailable.switcher") == nil, "old key is not copied")
        #expect(report.mappedSwitches == ["shell.enabled.cleaner", "shell.enabled.switcher"])
        #expect(report.alreadyPresentKeys == ["shell.enabled.mixer"])
        #expect(report.typeMismatchKeys == ["featureAvailable.", "featureAvailable.bad"])
    }

    @Test func skipListAndUnknownKeysAreNeverWritten() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        let report = try b.migrator([
            "notchDownloadsFolderBookmark": Data([1, 2]),
            "fanControlHelperVersion": "9",
            "commandBarQueryHabitKey": "x",
            "onboardingStep": 3,
            "whatsNewSeenVersion": "3.4.2",
            "vorssDisabledSleep": true,
            "NSWindow Frame Main": "0 0 1 1",
            "SUEnableAutomaticChecks": true,
            "someFutureThing": 1,
        ]).runV2()
        for key in ["notchDownloadsFolderBookmark", "fanControlHelperVersion", "commandBarQueryHabitKey",
                    "onboardingStep", "whatsNewSeenVersion", "vorssDisabledSleep",
                    "NSWindow Frame Main", "SUEnableAutomaticChecks", "someFutureThing"] {
            #expect(b.defaults.object(forKey: key) == nil, "\(key) must not be carried")
        }
        #expect(report.skippedKeys.contains("onboardingStep"))
        #expect(report.skippedKeys.contains("notchDownloadsFolderBookmark"))
        #expect(report.unknownKeys.sorted() == ["NSWindow Frame Main", "SUEnableAutomaticChecks", "someFutureThing"])
        #expect(report.carriedKeys.isEmpty)
    }

    @Test func secondRunIsANoOp() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        let domain: [String: Any] = ["batteryLimitPercent": 25]
        _ = try b.migrator(domain).runV2()
        b.defaults.set(40, forKey: "batteryLimitPercent")
        b.defaults.removeObject(forKey: "keepAwakeAutoStart")

        let second = try b.migrator(["batteryLimitPercent": 25, "keepAwakeAutoStart": true]).runV2()
        #expect(second.alreadyDone)
        #expect(b.defaults.integer(forKey: "batteryLimitPercent") == 40)
        #expect(b.defaults.object(forKey: "keepAwakeAutoStart") == nil)
        #expect(b.backups().count == 1, "no second backup")
    }

    @Test func backupExistsAndIsCompleteBeforeTheKeysAreWritten() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        let report = try b.migrator(["batteryLimitPercent": 25, "commandBarQueryHabitKey": "x"]).runV2()
        let backup = try #require(report.backupURL)
        #expect(backup.lastPathComponent.hasPrefix("vorssaint-v2-"))
        let data = try Data(contentsOf: backup.appendingPathComponent("preferences.plist"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["batteryLimitPercent"] as? Int == 25)
        #expect(plist["commandBarQueryHabitKey"] as? String == "x", "the backup keeps skipped keys too")
    }

    @Test func aFailedBackupWritesNothingAndDoesNotMarkDone() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        try FileManager.default.createDirectory(at: b.destSupport, withIntermediateDirectories: true)
        try "block".write(to: b.destSupport.appendingPathComponent("Backups"), atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try b.migrator(["batteryLimitPercent": 25]).runV2() }
        #expect(b.defaults.object(forKey: "batteryLimitPercent") == nil)
        #expect(b.defaults.bool(forKey: VorssaintMigrator.doneKeyV2) == false)
    }

    @Test func emptySourceDoesNotMarkDone() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        let report = try b.migrator([:]).runV2()
        #expect(report.nothingToMigrate)
        #expect(b.defaults.bool(forKey: VorssaintMigrator.doneKeyV2) == false)
        #expect(b.backups().isEmpty)
    }

    @Test func nothingToWriteMakesNoBackupButStillMarksDone() throws {
        let b = try BenchV2(); defer { b.cleanup() }
        b.defaults.set(10, forKey: "batteryLimitPercent")
        let report = try b.migrator(["batteryLimitPercent": 25]).runV2()
        #expect(report.backupURL == nil)
        #expect(b.defaults.bool(forKey: VorssaintMigrator.doneKeyV2))
    }
}
