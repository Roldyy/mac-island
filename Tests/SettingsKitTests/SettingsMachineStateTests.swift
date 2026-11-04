import Foundation
import Testing
@testable import SettingsKit

/// `SettingsMachineState` is the one list behind the backup, the v2 import and its purge.
@Suite struct SettingsMachineStateTests {
    @Test func theMigratorsMarkerSetIsTheSharedOne() {
        #expect(VorssaintMigrator.runtimeMarkerKeysV2 == SettingsMachineState.runtimeMarkers)
        #expect(SettingsMachineState.excludedKeys.isSuperset(of: SettingsMachineState.runtimeMarkers))
        #expect(SettingsMachineState.excludedKeys.isSuperset(of: SettingsMachineState.ownStateKeys))
    }

    @Test func ownConsentsAndJournalsAreExcludedButNotImportedKeysOrPurged() {
        for key in ["systemShortcutTakeOverKeys.macisland", "switcherTakeOverConsent.macisland",
                    "macIslandClosedLidConfirmed", "macisland.mixer.audioCaptureProbeStatus"] {
            #expect(SettingsMachineState.isExcluded(key), "\(key) would travel in a backup")
            #expect(!VorssaintMigrator.runtimeMarkerKeysV2.contains(key),
                    "\(key) is this app's own consent: the old-app purge must not remove it")
        }
    }

    @Test func safetyKeysAndTheBookmarkAreExcludedButNotPurged() {
        for key in ["macIslandOverlaySpaceCrashed", "macIslandOverlaySpaceKill", "macisland.musicAdapter.disabled",
                    "shell.killSwitch", "shell.safeMode", "notchDownloadsFolderBookmark",
                    "shell.crashCount.finder", "shell.crashCount.", "shell.hubSeeded"] {
            #expect(SettingsMachineState.isExcluded(key), "\(key) would travel in a backup")
        }
        for key in ["macIslandOverlaySpaceCrashed", "macIslandOverlaySpaceKill", "macisland.musicAdapter.disabled",
                    "shell.killSwitch", "shell.safeMode"] {
            #expect(!VorssaintMigrator.runtimeMarkerKeysV2.contains(key), "\(key) is this app's own state, never purged")
        }
    }

    @Test func onlyFeatureSwitchesOfTheShellNamespaceAreSettings() {
        #expect(!SettingsMachineState.isExcluded("shell.enabled.finder"))
        #expect(SettingsMachineState.isExcluded("shell.anythingElse"))
        #expect(SettingsMachineState.isExcluded("shell.enabledX"), "the prefix is `shell.enabled.` with its dot")
        #expect(!SettingsMachineState.isExcluded("shellfish"))
    }

    @Test func theOldAppsRuntimeStateIsExcludedByPrefix() {
        #expect(SettingsMachineState.isExcluded("vorssDisabledSleep"))
        #expect(SettingsMachineState.isExcluded("vorssDimmedDisplaySavedBrightness"))
        #expect(!SettingsMachineState.isExcluded("batteryLimitPercent"))
        #expect(!SettingsMachineState.isExcluded("macisland.recorder.maxMinutes"))
    }

    @Test func thePurgeStillRemovesTheMarkersAndKeepsTheOwnConsents() {
        let name = "mis-test-purge-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "bluetoothSleepRestorePending")
        defaults.set(true, forKey: "macIslandClosedLidConfirmed")
        #expect(VorssaintMigrator.purgeRuntimeKeysV2(in: defaults) == 1)
        #expect(defaults.object(forKey: "bluetoothSleepRestorePending") == nil)
        #expect(defaults.bool(forKey: "macIslandClosedLidConfirmed"))
    }

    /// The guard's switch re-applies default handlers on its own, so a restored file must never turn it on.
    @Test func theDefaultAppsGuardSwitchIsThisMacsConsentNeverBackedUpNorPurged() {
        #expect(SettingsMachineState.isExcluded("defaultAppsGuardEnabled"))
        #expect(SettingsMachineState.ownStateKeys.contains("defaultAppsGuardEnabled"))
        #expect(!VorssaintMigrator.runtimeMarkerKeysV2.contains("defaultAppsGuardEnabled"), "the user's own choice is not purged either")
        let name = "mis-test-guard-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(VorssaintMigrator.purgeRuntimeKeysV2(in: defaults) == 0)
        #expect(defaults.bool(forKey: "defaultAppsGuardEnabled") == false)
    }
}
