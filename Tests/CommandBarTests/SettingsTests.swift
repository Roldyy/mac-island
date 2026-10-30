import Foundation
import Testing
@testable import CommandBarFeature

@Suite final class SettingsTests {
    let bag = DefaultsBag()

    @Test func keyNamesAreStable() {
        #expect(CommandBarSettings.enabledKey == "commandBarEnabled")
        #expect(CommandBarSettings.hotkeyKey == "commandBarHotkey")
        #expect(CommandBarSettings.habitsKey == "commandBarHabitsEnabled")
        // The old app's secret-looking key is never read.
        let all = [CommandBarSettings.enabledKey, CommandBarSettings.hotkeyKey, CommandBarSettings.habitsKey]
            + ["apps", "files", "calculator", "web", "commands"].map(CommandBarSettings.sourceKey)
        #expect(!all.contains("commandBarQueryHabitKey"))
        #expect(CommandBarSettings.sourceKey("apps") == "commandBarSourceApps")
    }

    @Test func defaults() {
        let s = CommandBarSettings(defaults: bag.makeDefaults())
        #expect(s.enabled)
        #expect(s.habitsEnabled)
        #expect(s.hotkey == .default)
        for id in ["apps", "files", "calculator", "web", "commands"] { #expect(s.sourceEnabled(id)) }
    }

    @Test func writesAndReads() {
        let d = bag.makeDefaults()
        let s = CommandBarSettings(defaults: d)
        s.enabled = false
        s.habitsEnabled = false
        s.setSource("files", enabled: false)
        s.hotkeyRaw = "option+command:9"
        let r = CommandBarSettings(defaults: d)
        #expect(!r.enabled && !r.habitsEnabled && !r.sourceEnabled("files") && r.sourceEnabled("apps"))
        #expect(r.hotkey.stored == "option+command:9")
    }

    @Test func unparseableHotkeyFallsBackToDefault() {
        let d = bag.makeDefaults()
        d.set("garbage", forKey: CommandBarSettings.hotkeyKey)
        #expect(CommandBarSettings(defaults: d).hotkey == .default)
    }
}
