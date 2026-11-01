import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit
@testable import IPScannerFeature

@MainActor
@Suite struct IPScannerRegistrationTests {
    let bench = TestDefaults.make()
    let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))

    func registry() -> FeatureRegistry {
        FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker, withdraw: { _ in })
    }

    @Test func theTabHasAStableIdentityAndAFrenchTitle() {
        let tab = IPScannerFeature.tab()
        #expect(tab.id == "ipscanner" && tab.title == "Réseau local")
        #expect(!tab.title.localizedCaseInsensitiveContains("bient"))
    }

    @Test func theDescriptorIsRegisteredOnceAndOffByDefault() {
        defer { bench.cleanup(); marker.clear() }
        let matches = ShellDescriptors.all.filter { $0.id == "ipscanner" }
        #expect(matches.count == 1)
        let d = matches[0]
        #expect(d.tabID == IPScannerFeature.tab().id && !d.enabledByDefault && d.permissions.isEmpty)
        #expect(registry().state(for: "ipscanner") == .off)
    }

    @Test func theSettingsPageIsInTheCatalogWithTheFeatureSwitch() throws {
        let page = try #require(SettingsPageCatalog.page("ipscanner"))
        #expect(page.title == "Scanner IP" && page.featureID == "ipscanner" && page.id == IPScannerFeature.pageID)
        #expect(!page.summary.contains("Bientôt") && page.kind == .declarative)
        #expect(SettingsPageCatalog.all.filter { $0.id == "ipscanner" }.count == 1)
    }

    @Test func theSettingsBodyMakesThePageLiveNotComingSoon() throws {
        SettingsPageBodies.register(pageID: IPScannerFeature.pageID) { IPScannerFeature.settingsBody() }
        defer { SettingsPageBodies.removeAll() }
        let page = try #require(SettingsPageCatalog.page("ipscanner"))
        #expect(SettingsPageBodies.hasBody(for: "ipscanner") && !page.isComingSoon)
        #expect(SettingsPageModel.blocks(for: page).isEmpty, "no greyed placeholder rows: the body is the page")
    }

    @Test func theRegistryStartsAndStopsTheFeatureAndTheKillSwitchStopsIt() {
        defer { bench.cleanup(); marker.clear() }
        let r = registry()
        var events: [String] = []
        r.launch(starters: ["ipscanner": { events.append("start") }], stoppers: ["ipscanner": { events.append("stop") }])
        #expect(events.isEmpty, "off by default: launching the app starts nothing")
        r.switches["ipscanner"] = true
        #expect(events == ["start"])
        r.killSwitch = true
        #expect(events == ["start", "stop"], "the kill switch stops it")
        r.killSwitch = false
        #expect(events == ["start", "stop", "start"])
        r.safeMode = true
        #expect(events.last == "stop", "safe mode keeps only the daily features")
    }
}
