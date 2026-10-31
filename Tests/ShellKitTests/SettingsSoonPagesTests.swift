import Testing
@testable import ShellKit

@Suite struct SettingsSoonPagesTests {
    @Test func comingSoonPagesExposeNoEnabledControl() {
        let soon = SettingsPageCatalog.all.filter(\.isComingSoon)
        #expect(soon.count > 20)
        for page in soon {
            #expect(SettingsPageModel.enabledToggles(for: page).isEmpty, "\(page.id)")
            #expect(SettingsPageModel.blocks(for: page).flatMap(\.rows).allSatisfy { !$0.isEnabled }, "\(page.id)")
        }
    }

    @Test func plannedRowsOnMixedPagesAreDisabledToo() {
        let page = SettingsPageCatalog.page("keepawake")!
        let rows = SettingsPageModel.blocks(for: page).flatMap(\.rows)
        let live = rows.filter(\.isLive)
        #expect(live.count >= 4)
        let suspended = rows.first { $0.item.label == "Suspendre lorsque le Mac est verrouillé" }
        #expect(suspended?.isEnabled == false)
    }

    @Test func realFeaturePagesHaveLiveControls() {
        for id in ["keepawake", "dockclicks", "clipboard", "commandbar", "monitor", "shelf", "cutpaste"] {
            let page = SettingsPageCatalog.page(id)!
            #expect(SettingsPageModel.blocks(for: page).flatMap(\.rows).contains { $0.isLive }, "\(id)")
        }
    }

    @Test func liveKeysAreTheMigratedNames() {
        let keys = SettingsLive.table.values.flatMap { $0.bound.values.map(\.key) + $0.extras.map(\.key) }
        for key in ["defaultDurationMinutes", "dockClickMinimize", "clipboardHistoryEnabled", "pastePlainShortcut", "finderCutPasteEnabled"] {
            #expect(keys.contains(key), "\(key)")
        }
    }

    @Test func itemParsing() {
        #expect(SettingsItem.parse("T|Hello")?.kind == .toggle)
        #expect(SettingsItem.parse("S|A|x;y|y")?.options == ["x", "y"])
        #expect(SettingsItem.parse("X|nope") == nil)
    }
}
