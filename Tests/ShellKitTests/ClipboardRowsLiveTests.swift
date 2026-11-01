import AppKit
import Foundation
import Testing
@testable import ShellKit

/// The history and plain-paste pages: every row is backed by a real control, an action or a readout.
@MainActor
@Suite struct ClipboardRowsLiveTests {
    private func planned(_ id: String) -> [String] {
        let page = SettingsPageCatalog.page(id)!
        return SettingsPageModel.blocks(for: page).flatMap(\.rows)
            .filter { !$0.isLive && $0.item.kind != .caption && $0.item.kind != .heading }
            .map(\.item.label)
    }

    @Test func noRowOfTheTwoPagesIsPlannedAnyMore() {
        #expect(planned("clipboard").isEmpty, "\(planned("clipboard"))")
        #expect(planned("pasteplain").isEmpty, "\(planned("pasteplain"))")
        #expect(!SettingsPageCatalog.page("clipboard")!.isComingSoon)
        #expect(!SettingsPageCatalog.page("pasteplain")!.isComingSoon)
    }

    @Test func theRowsAreBoundToTheMigratedVorssaintKeys() throws {
        let clip = try #require(SettingsLive.controls(for: "clipboard"))
        let keys = Set(clip.bound.values.map(\.key))
        for key in [
            "clipboardHistoryEnabled", "clipboardHistoryShortcutEnabled", "clipboardHistoryShortcut",
            "clipboardHistoryLayout", "clipboardHistoryMenuBarPreview", "clipboardHistoryMenuBarPreviewLength",
            "clipboardHistoryIncludeImagesFiles", "clipboardHistoryFilterSensitiveText", "clipboardHistoryLimit",
            "clipboardHistoryRetentionDays", "panelUtilityClipboard", "clipboardAutoClearOnDelay",
            "clipboardAutoClearDelaySeconds", "clipboardAutoClearOnSleep", "clipboardAutoClearOnDisplaySleep",
            "clipboardAutoClearOnScreenLock", "finderPasteImageAsFile",
        ] { #expect(keys.contains(key), "\(key)") }
        let plain = try #require(SettingsLive.controls(for: "pasteplain"))
        #expect(plain.bound["Effacer non épinglés"]?.kind == .action(title: "Effacer", confirm: "Confirmer l’effacement"))
        #expect(plain.bound["Épinglés"]?.kind == .readout && plain.bound["Récents"]?.kind == .readout)
    }

    @Test func theLayoutChoiceStoresListOrCardsAndRejectsAnythingElse() throws {
        let suite = NSTemporaryDirectory() + "shell-clip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LiveStore(defaults: defaults)
        let control = try #require(SettingsLive.controls(for: "clipboard")?.bound[""])
        #expect(control.key == "clipboardHistoryLayout")
        #expect(store.string(control) == "list", "nothing stored: the list")
        store.setString("cards", control)
        #expect(defaults.string(forKey: "clipboardHistoryLayout") == "cards")
        #expect(store.string(control) == "cards")
        store.setString("grid", control)
        #expect(defaults.string(forKey: "clipboardHistoryLayout") == "cards", "an unknown value is never written")
        defaults.set("garbage", forKey: "clipboardHistoryLayout")
        #expect(store.string(control) == "list", "a stored garbage value reads as the default")
    }

    @Test func retentionAndPreviewLengthKeepTheirOwnRanges() throws {
        let clip = try #require(SettingsLive.controls(for: "clipboard"))
        let length = try #require(clip.bound["Longueur de l’aperçu"])
        guard case let .stepper(range, fallback, unit) = length.kind else { Issue.record("not a stepper"); return }
        #expect(range == 5...50 && fallback == 20 && unit == "caractères")
        let retention = try #require(clip.bound["Conserver les éléments"])
        guard case let .choice(options, fallback) = retention.kind else { Issue.record("not a menu"); return }
        #expect(fallback == 0 && options.first?.value == 0 && options.map(\.value) == [0, 1, 7, 30, 90, 365])
    }

    @Test func actionsAndReadoutsComeFromTheHostAndAnUnregisteredOneIsInert() {
        SettingsActions.removeAll()
        defer { SettingsActions.removeAll() }
        #expect(!SettingsActions.hasAction("x") && SettingsActions.readout("x") == "")
        SettingsActions.run("x")   // no crash
        var ran = 0
        SettingsActions.register(action: "x") { ran += 1 }
        SettingsActions.register(readout: "n") { "7" }
        SettingsActions.run("x")
        #expect(ran == 1 && SettingsActions.hasAction("x") && SettingsActions.readout("n") == "7")
    }

    @Test func aClickOnThePreviewTextOpensTheHistoryAClickOnTheIconKeepsThePanel() {
        #expect(MenuBarItemController.opensHistory(previewShown: true, clickX: 40, iconTrailingEdge: 24))
        #expect(!MenuBarItemController.opensHistory(previewShown: true, clickX: 12, iconTrailingEdge: 24))
        #expect(!MenuBarItemController.opensHistory(previewShown: false, clickX: 40, iconTrailingEdge: 24),
                "without a preview the whole button is the icon")
    }
}
