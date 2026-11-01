import Foundation
import Testing
@testable import SettingsKit

/// `featureAvailable.<upstream id>` lands on the switch the registry reads, and a Mac where pass 2 already
/// wrote the upstream-named key is repaired once. Throwaway suites in a temp folder only.
@Suite struct VorssaintSwitchIDTests {
    private func makeSuite() -> (UserDefaults, () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-tests-switchid-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = root.appendingPathComponent("prefs").path
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        })
    }

    @Test func theMappingTableCoversTheFiveRenamedFeatures() {
        #expect(VorssaintMigrator.upstreamToRegistryID["keepAwake"] == "keepawake")
        #expect(VorssaintMigrator.upstreamToRegistryID["clipboardHistory"] == "clipboard")
        #expect(VorssaintMigrator.upstreamToRegistryID["commandBar"] == "commandbar")
        #expect(VorssaintMigrator.upstreamToRegistryID["mixer"] == "audio")
        #expect(VorssaintMigrator.upstreamToRegistryID["fanControl"] == "fans")
    }

    @Test func theTwoDockSwitchesShareTheDockSwitch() {
        #expect(VorssaintMigrator.upstreamToRegistryID["dockPreview"] == "dock")
        #expect(VorssaintMigrator.upstreamToRegistryID["dockClick"] == "dock")
    }

    @Test func twoStrayDockSwitchesRepairIntoOneSwitchOnWhenEitherWasOn() {
        for (preview, click, expected) in [(true, false, true), (false, true, true), (false, false, false)] {
            let (defaults, cleanup) = makeSuite()
            defer { cleanup() }
            defaults.set(preview, forKey: "shell.enabled.dockPreview")
            defaults.set(click, forKey: "shell.enabled.dockClick")
            #expect(VorssaintMigrator.repairSwitchIDsV2(in: defaults) == 1)
            #expect(defaults.object(forKey: "shell.enabled.dock") as? Bool == expected, "preview \(preview), click \(click)")
            #expect(defaults.object(forKey: "shell.enabled.dockPreview") == nil)
            #expect(defaults.object(forKey: "shell.enabled.dockClick") == nil)
        }
    }

    @Test func aStraySwitchMovesToTheRegistryKeyOnce() {
        let (defaults, cleanup) = makeSuite()
        defer { cleanup() }
        defaults.set(true, forKey: "shell.enabled.keepAwake")
        defaults.set(false, forKey: "shell.enabled.mixer")
        defaults.set(true, forKey: "shell.enabled.audio") // already decided by the user: never overwritten
        defaults.set(true, forKey: "shell.enabled.scrollInverter") // not renamed: untouched

        let moved = VorssaintMigrator.repairSwitchIDsV2(in: defaults)

        #expect(moved == 1)
        #expect(defaults.object(forKey: "shell.enabled.keepAwake") == nil)
        #expect(defaults.bool(forKey: "shell.enabled.keepawake") == true)
        #expect(defaults.object(forKey: "shell.enabled.mixer") == nil)
        #expect(defaults.bool(forKey: "shell.enabled.audio") == true)
        #expect(defaults.bool(forKey: "shell.enabled.scrollInverter") == true)
        // Second call does nothing.
        defaults.set(true, forKey: "shell.enabled.commandBar")
        #expect(VorssaintMigrator.repairSwitchIDsV2(in: defaults) == 0)
        #expect(defaults.object(forKey: "shell.enabled.commandBar") != nil)
    }
}
