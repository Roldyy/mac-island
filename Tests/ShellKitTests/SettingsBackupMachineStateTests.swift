import Foundation
import SettingsKit
import Testing
@testable import ShellKit

/// A settings backup carries preferences. The runtime markers, consents, evidence and journals of one boot never
/// travel in it, and a restore never writes them back (an old file may still hold them). Throwaway suites only.
@Suite struct SettingsBackupMachineStateTests {
    private static let preferences: [String: Any] = ["dockPreviewEnabled": true, "batteryLimitPercent": 25]

    /// Every key the audit named, one of each kind.
    private static let machineState: [String: Any] = [
        "systemShortcutsSuppressed": [3, 4], "superKeyMappingApplied": true, "superKeyMappedSource": "capsLock",
        "vorssDisabledSleep": true, "vorssDimmedDisplaySavedBrightness": 0.4, "spacesOrderRestore": true,
        "bluetoothSleepRestorePending": true, "micMuteActive": true, "micMuteSavedVolume": 0.6,
        "micMuteSavedVolumes": ["uid": 0.5], "micMuteSavedChannelVolumes": ["uid": ["1": 0.5]],
        "displaysSwitchedOff": ["1"], "displaysSwitchedOffFingerprints": ["x"],
        "systemShortcutTakeOverKeys.macisland": [3], "macIslandClosedLidConfirmed": true,
        "switcherTakeOverConsent.macisland": true, "macisland.mixer.audioCaptureProbeStatus": "denied",
        "macIslandDisplayGammaDimActive": true, "quickToggles.finderJournal.macisland": "x",
    ]

    private func bench() throws -> (defaults: UserDefaults, domain: String, dir: URL, cleanup: () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-backup-ms-\(UUID().uuidString)")
        let domain = "mis-test-ms-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defaults.removePersistentDomain(forName: domain)
        return (defaults, domain, dir, {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: dir)
        })
    }

    private func plist(_ url: URL) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    @Test func theExportCarriesPreferencesAndNoMachineState() throws {
        let b = try bench(); defer { b.cleanup() }
        for (key, value) in Self.preferences.merging(Self.machineState, uniquingKeysWith: { a, _ in a }) {
            b.defaults.set(value, forKey: key)
        }
        let file = try SettingsBackup(defaults: b.defaults, domain: b.domain, directory: b.dir).export()
        let exported = try plist(file)
        #expect(exported["dockPreviewEnabled"] as? Bool == true)
        #expect(exported["batteryLimitPercent"] as? Int == 25)
        for key in Self.machineState.keys { #expect(exported[key] == nil, "\(key) was exported") }
    }

    @Test func aRestoreOfAnOldFileNeverWritesMachineStateAndLeavesLiveKeysAlone() throws {
        let b = try bench(); defer { b.cleanup() }
        try FileManager.default.createDirectory(at: b.dir, withIntermediateDirectories: true)
        // An old backup written before this change: preferences plus every marker and consent.
        let old = b.dir.appendingPathComponent("settings-20260101-000000.plist")
        let all = Self.preferences.merging(Self.machineState, uniquingKeysWith: { a, _ in a })
        try PropertyListSerialization.data(fromPropertyList: all, format: .xml, options: 0).write(to: old)

        // A live marker of this boot is neither overwritten nor deleted.
        b.defaults.set(false, forKey: "micMuteActive")
        b.defaults.set(true, forKey: "macIslandClosedLidConfirmed")
        let backup = SettingsBackup(defaults: b.defaults, domain: b.domain, directory: b.dir)
        try backup.restore(from: old)

        #expect(b.defaults.bool(forKey: "dockPreviewEnabled"))
        #expect(b.defaults.integer(forKey: "batteryLimitPercent") == 25)
        for key in Self.machineState.keys where key != "micMuteActive" && key != "macIslandClosedLidConfirmed" {
            #expect(b.defaults.object(forKey: key) == nil, "\(key) came back from the file")
        }
        #expect(b.defaults.object(forKey: "micMuteActive") as? Bool == false, "a live marker is left alone")
        #expect(b.defaults.bool(forKey: "macIslandClosedLidConfirmed"), "a live consent is not deleted")
    }

    @Test func theBackupAndTheMigratorShareOneList() {
        for key in SettingsMachineState.runtimeMarkers {
            #expect(SettingsBackup.isLeftOut(key), "\(key) is a runtime marker the backup would carry")
        }
        for key in SettingsMachineState.ownStateKeys {
            #expect(SettingsBackup.isLeftOut(key))
        }
        #expect(SettingsBackup.isLeftOut("NSWindow Frame x"))
        #expect(!SettingsBackup.isLeftOut("dockPreviewEnabled"))
        #expect(!SettingsBackup.isLeftOut("macisland.recorder.maxMinutes"), "a Mac Island preference still travels")
    }
}
