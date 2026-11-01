import Foundation
import Testing
@testable import SettingsKit

/// Crash and runtime markers of the old app are never carried, and a Mac that already carried them is cleaned
/// once. Throwaway suites in a temp folder only.
@Suite struct VorssaintRuntimeMarkerTests {
    private static let required: [String] = [
        "fanControlRecoveryNeeded", "fanControlResume", "fanControlResumeConfiguration",
        "superKeyMappingApplied", "superKeyMappedSource", "clamshellPreferred", "wallpaperOwnBookmarks",
        "systemShortcutsSuppressed", "switcherNativeHotkeysSuppressed", "dockPreviewRestoreAutohide",
        "spacesOrderRestore", "spacesOrderRestartPending", "bluetoothSleepRestorePending",
        "micMuteActive", "micMuteSavedVolume", "micMuteSavedVolumes", "micMuteSavedChannelVolumes",
        "micMuteMutedDevices", "displaysSwitchedOff", "displaysSwitchedOffFingerprints", "startupDidNotFinish",
    ]

    private func makeSuite() -> (UserDefaults, () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-tests-markers-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = root.appendingPathComponent("prefs").path
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        })
    }

    @Test func everyMarkerIsAKnownKeyAndIsSkipped() {
        for key in Self.required {
            #expect(VorssaintKnownKeys.all.contains(key), "\(key) is not a known key")
            #expect(VorssaintMigrator.isSkippedV2(key), "\(key) would be carried")
        }
        #expect(Set(Self.required) == VorssaintMigrator.runtimeMarkerKeysV2)
        // The pre-existing exact skips and the prefix rule still hold.
        #expect(VorssaintMigrator.isSkippedV2("notchDownloadsFolderBookmark"))
        #expect(VorssaintMigrator.isSkippedV2("vorssDisabledSleep"))
        #expect(VorssaintMigrator.isSkippedV2("vorssDimmedDisplaySavedBrightness"))
    }

    @Test func v2DoesNotCarryTheMarkersButCarriesPreferences() throws {
        let (defaults, cleanup) = makeSuite(); defer { cleanup() }
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("mis-m-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        var source: [String: Any] = ["batteryLimitPercent": 25]
        for key in ["fanControlRecoveryNeeded", "superKeyMappingApplied", "clamshellPreferred"] { source[key] = true }
        source["superKeyMappedSource"] = "capsLock"
        let report = try VorssaintMigrator(
            sourceDomain: source, sourceSupportDir: nil, destDefaults: defaults, destSupportDir: support,
            now: { Date(timeIntervalSince1970: 1_790_000_000) }).runV2()
        #expect(defaults.integer(forKey: "batteryLimitPercent") == 25)
        for key in ["fanControlRecoveryNeeded", "superKeyMappingApplied", "clamshellPreferred", "superKeyMappedSource"] {
            #expect(defaults.object(forKey: key) == nil, "\(key) was carried")
            #expect(report.skippedKeys.contains(key))
        }
    }

    @Test func purgeRemovesExactlyTheMarkersOnceAndReturnsACount() {
        let (defaults, cleanup) = makeSuite(); defer { cleanup() }
        for key in Self.required.prefix(5) { defaults.set(true, forKey: key) }
        defaults.set(25, forKey: "batteryLimitPercent")
        defaults.set(true, forKey: "shell.enabled.keepAwake")
        #expect(VorssaintMigrator.purgeRuntimeKeysV2(in: defaults) == 5)
        for key in Self.required { #expect(defaults.object(forKey: key) == nil) }
        #expect(defaults.integer(forKey: "batteryLimitPercent") == 25)
        #expect(defaults.bool(forKey: "shell.enabled.keepAwake"))
        #expect(defaults.bool(forKey: VorssaintMigrator.purgeRuntimeKeysDoneKey))
        #expect(VorssaintMigrator.purgeRuntimeKeysDoneKey == "migration.v2.purgeRuntimeKeys.done")
    }

    @Test func purgeIsOneShot() {
        let (defaults, cleanup) = makeSuite(); defer { cleanup() }
        #expect(VorssaintMigrator.purgeRuntimeKeysV2(in: defaults) == 0)
        // A marker written afterwards (a bound service, later) is never removed by a second launch.
        defaults.set(true, forKey: "fanControlRecoveryNeeded")
        #expect(VorssaintMigrator.purgeRuntimeKeysV2(in: defaults) == 0)
        #expect(defaults.bool(forKey: "fanControlRecoveryNeeded"))
    }
}
