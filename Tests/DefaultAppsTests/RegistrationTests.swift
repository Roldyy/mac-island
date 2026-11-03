import Foundation
import IslandKit
import IslandTestSupport
import SettingsKit
import Testing
@testable import ShellKit
@testable import DefaultAppsFeature

@MainActor
@Suite struct DefaultAppsRegistrationTests {
    let bench = TestDefaults.make()
    let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))

    func registry() -> FeatureRegistry {
        FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker, withdraw: { _ in })
    }

    @Test func theTabHasAStableIdentityAndAFrenchTitle() {
        let tab = DefaultAppsFeature.tab()
        #expect(tab.id == "defaultapps" && tab.title == "Apps par défaut")
        #expect(!tab.title.localizedCaseInsensitiveContains("bient"))
    }

    @Test func theDescriptorIsRegisteredOnceAndOffByDefault() {
        defer { bench.cleanup(); marker.clear() }
        let matches = ShellDescriptors.all.filter { $0.id == "defaultapps" }
        #expect(matches.count == 1)
        let d = matches[0]
        #expect(d.tabID == DefaultAppsFeature.tab().id && !d.enabledByDefault && d.permissions.isEmpty)
        #expect(registry().state(for: "defaultapps") == .off)
    }

    @Test func theSettingsPageIsInTheCatalogWithTheFeatureSwitch() throws {
        let page = try #require(SettingsPageCatalog.page("defaultapps"))
        #expect(page.title == "Applications par défaut" && page.featureID == "defaultapps" && page.id == DefaultAppsFeature.pageID)
        #expect(!page.summary.contains("Bientôt") && page.kind == .declarative)
        #expect(SettingsPageCatalog.all.filter { $0.id == "defaultapps" }.count == 1)
    }

    @Test func theSettingsBodyMakesThePageLiveNotComingSoon() throws {
        SettingsPageBodies.register(pageID: DefaultAppsFeature.pageID) { DefaultAppsFeature.settingsBody() }
        defer { SettingsPageBodies.removeAll() }
        let page = try #require(SettingsPageCatalog.page("defaultapps"))
        #expect(SettingsPageBodies.hasBody(for: "defaultapps") && !page.isComingSoon)
        #expect(SettingsPageModel.blocks(for: page).isEmpty, "no greyed placeholder rows: the body is the page")
    }

    @Test func theHomeTileExistsDimmedWhileTheFeatureIsOff() {
        let features = ShellDescriptors.all.map { HomeFeature(id: $0.id, title: $0.title, systemImage: $0.systemImage) }
        let tiles = HomeTileCatalog.merged(actions: [], features: features, enabled: { $0 != "defaultapps" }, hidden: [])
        let tile = tiles.first { $0.id == "defaultapps" }
        #expect(tile?.title == "Apps par défaut" && tile?.isEnabled == false)
        #expect(HomeTileCatalog.merged(actions: [], features: features, enabled: { _ in true }, hidden: []).first { $0.id == "defaultapps" }?.isEnabled == true)
    }

    @Test func theRegistryStartsAndStopsTheFeatureAndTheKillSwitchStopsIt() {
        defer { bench.cleanup(); marker.clear() }
        let r = registry()
        var events: [String] = []
        r.launch(starters: ["defaultapps": { events.append("start") }], stoppers: ["defaultapps": { events.append("stop") }])
        #expect(events.isEmpty, "off by default: launching the app starts nothing")
        r.switches["defaultapps"] = true
        #expect(events == ["start"])
        r.killSwitch = true
        #expect(events == ["start", "stop"], "the kill switch stops it")
        r.killSwitch = false
        #expect(events == ["start", "stop", "start"])
        r.safeMode = true
        #expect(events.last == "stop", "safe mode keeps only the daily features")
    }

    @Test func theJournalChoicesAndGuardTimesNeverTravelInABackup() {
        for key in ["defaultAppsJournal", "defaultAppsJournal.corrupt", "defaultAppsChoices", "defaultAppsGuardLast"] {
            #expect(SettingsMachineState.isExcluded(key), Comment(rawValue: key))
        }
        #expect(DefaultAppsJournalStore.key == "defaultAppsJournal")
        #expect(!SettingsMachineState.isExcluded(DefaultAppsSettings.guardKey), "the opt-in switch is a plain preference")
    }

    @Test func logsUseTheDefaultappsCategory() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/DefaultApps/DefaultAppsEnvironment.swift"), encoding: .utf8)
        #expect(source.contains("category: \"defaultapps\""))
    }
}
