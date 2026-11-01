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
        // Keep Awake used to be the mixed page of this test; its ported body now draws it whole. Any page that
        // still mixes live and planned rows must keep the planned ones inert.
        func isPlanned(_ row: SettingsRow) -> Bool {
            !row.isLive && row.item.kind != .caption && row.item.kind != .heading
        }
        var mixed = 0
        for page in SettingsPageCatalog.all {
            let rows = SettingsPageModel.blocks(for: page).flatMap(\.rows)
            guard rows.contains(where: \.isLive), rows.contains(where: isPlanned) else { continue }
            mixed += 1
            for row in rows where isPlanned(row) { #expect(!row.isEnabled, "\(page.id): \(row.item.label)") }
        }
        #expect(mixed >= 1)
    }

    @Test func realFeaturePagesHaveLiveControls() {
        for id in ["clipboard", "monitor", "cutpaste"] {  // shelf and commandbar are ported body pages now
            let page = SettingsPageCatalog.page(id)!
            #expect(SettingsPageModel.blocks(for: page).flatMap(\.rows).contains { $0.isLive }, "\(id)")
        }
    }

    @Test func liveKeysAreTheMigratedNames() {
        let keys = SettingsLive.table.values.flatMap { $0.bound.values.map(\.key) + $0.extras.map(\.key) }
        for key in ["notchIdleShowKeepAwake", "clipboardHistoryEnabled", "pastePlainShortcut", "finderCutPasteEnabled"] {
            #expect(keys.contains(key), "\(key)")
        }
    }

    @Test func itemParsing() {
        #expect(SettingsItem.parse("T|Hello")?.kind == .toggle)
        #expect(SettingsItem.parse("S|A|x;y|y")?.options == ["x", "y"])
        #expect(SettingsItem.parse("X|nope") == nil)
    }
}
