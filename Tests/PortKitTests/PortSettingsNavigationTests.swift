import Foundation
import Testing
@testable import PortKit
@testable import ShellKit

/// Harold, 2026-11-02: "Ouvrir Fonctionnalites" did nothing. Upstream's views navigate through its own `SettingsRouter`,
/// which nothing in Mac Island observed. The mapping to OUR page ids is pure; the bridge forwards every request.
@MainActor
@Suite(.serialized) struct PortSettingsNavigationTests {
    static let allPages: [PortKit.SettingsPage] = [
        .general, .features, .energy, .monitor, .mouse, .switcher, .dock, .keyDebounce, .superKey, .cutPaste, .autoQuit,
        .quitProtection, .cleaner, .uninstaller, .urlCleaner, .homebrew, .appUpdates, .media, .clipboard, .windowLayout,
        .shelf, .quickTools, .textSnippets, .screenshot, .radialMenu, .commandBar, .killProcess, .portManager, .notch,
        .notchMascot, .shortcuts, .advanced, .about, .releaseNotes, .support,
    ]

    // MARK: Pure mapping

    @Test func everyUpstreamPageMapsToAPageOfOurCatalog() {
        for page in Self.allPages {
            let id = PortSettingsNavigation.pageID(for: page)
            #expect(SettingsPageCatalog.page(id) != nil, "\(page) -> \(id) is not a Settings page of Mac Island")
        }
    }

    @Test func everySectionAnchorMapsToAPageOfOurCatalog() {
        for anchor in SettingsSectionAnchor.allCases {
            let id = PortSettingsNavigation.pageID(for: anchor)
            #expect(SettingsPageCatalog.page(id) != nil, "\(anchor) -> \(id) is not a Settings page of Mac Island")
        }
    }

    @Test func everyFeatureDestinationLandsOnARealPage() {
        for feature in AppFeature.allCases {
            let id = PortSettingsNavigation.pageID(for: feature.settingsDestination)
            #expect(SettingsPageCatalog.page(id) != nil, "\(feature) -> \(id)")
        }
    }

    @Test func theFeaturesHubAndTheCompanionLandWhereHaroldExpects() {
        #expect(PortSettingsNavigation.pageID(for: FeatureSettingsDestination(.features)) == "features")
        #expect(PortSettingsNavigation.pageID(for: AppFeature.notch.settingsDestination) == "island")
        #expect(PortSettingsNavigation.pageID(for: FeatureSettingsDestination(.notchMascot)) == "island")
        #expect(PortSettingsNavigation.pageID(for: AppFeature.dockClick.settingsDestination) == "dockclicks")
        #expect(PortSettingsNavigation.pageID(for: AppFeature.brightness.settingsDestination) == "displays")
    }

    @Test func anAnchorOfAnotherPageIsIgnored() {
        // `.dockClick` belongs to `.dock`: asked on `.mouse` it is invalid, the page's own entry wins.
        let bad = FeatureSettingsDestination(.mouse, sectionAnchor: .dockClick)
        #expect(bad.hasValidSectionAnchor == false)
        #expect(PortSettingsNavigation.pageID(for: bad) == "scrollreverse")
    }

    // MARK: The bridge

    final class Opened: @unchecked Sendable {
        var ids: [String] = []
    }

    func bridge(_ router: PortKit.SettingsRouter, _ opened: Opened) -> PortSettingsBridge {
        PortSettingsBridge(router: router, open: { opened.ids.append($0) })
    }

    @Test func aRequestForTheFeaturesHubOpensOurFeaturesPage() {
        let router = PortKit.SettingsRouter()
        let opened = Opened()
        let bridge = bridge(router, opened)
        #expect(opened.ids.isEmpty, "subscribing forwards nothing (the router's first value is not a request)")
        bridge.flush()
        #expect(opened.ids.isEmpty)

        // What `AppFeature.notch.showInFeatures()` (the "Ouvrir Fonctionnalites" button) asks of the shared router.
        router.request(FeatureSettingsDestination(.features), targetFeature: .notch)
        bridge.flush()
        #expect(opened.ids == ["features"])
    }

    @Test func aRequestIsForwardedOnceWhateverItTouches() {
        let router = PortKit.SettingsRouter()
        let opened = Opened()
        let bridge = bridge(router, opened)
        // Page change, then destination: two publications, one word.
        router.request(AppFeature.dockClick.settingsDestination)
        bridge.flush()
        #expect(opened.ids == ["dockclicks"], "the anchor wins over the page's default, and only once")
    }

    @Test func settingThePageTwiceStillOpensItTheSecondTime() {
        // The shared router keeps its page: the user has moved on in our window, the same button must work again.
        let router = PortKit.SettingsRouter()
        let opened = Opened()
        let bridge = bridge(router, opened)
        router.page = .portManager
        bridge.flush()
        router.page = .portManager
        bridge.flush()
        #expect(opened.ids == ["ports", "ports"])
    }

    @Test func theCompanionRequestOpensTheIslandPage() {
        let router = PortKit.SettingsRouter()
        let opened = Opened()
        let bridge = bridge(router, opened)
        router.request(AppFeature.notchMascot.settingsDestination)
        bridge.flush()
        #expect(opened.ids == ["island"])
    }

    @Test func theScheduledFlushRunsOnItsOwn() async {
        let router = PortKit.SettingsRouter()
        let opened = Opened()
        let bridge = bridge(router, opened)
        router.page = .about
        let deadline = Date().addingTimeInterval(120)
        while opened.ids.isEmpty, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(opened.ids == ["about"])
        _ = bridge
    }

    // MARK: The facade

    @Test func theFacadeOpensThePageOrFallsBackToTheWindow() {
        var window = 0
        var pages: [String] = []
        let facade = AppDelegate()
        facade.openSettings = { window += 1 }
        facade.openSettingsPage(id: "features")
        #expect(window == 1 && pages.isEmpty, "no page door: the window opens")
        facade.openSettingsPage = { pages.append($0) }
        facade.openSettingsPage(id: "features")
        #expect(pages == ["features"] && window == 1)
    }

    @Test func feedbackOpensTheIssueFormAndTheIconComesBack() {
        var kinds: [FeedbackKind] = []
        var shown = 0
        let facade = AppDelegate()
        facade.openFeedback = { kinds.append($0) }
        facade.reshowIcon = { shown += 1 }
        facade.openFeedbackWindow()
        facade.openFeedbackWindow(kind: .feature)
        facade.reshowStatusItem()
        #expect(kinds == [.bug, .feature])
        #expect(shown == 1)
        #expect(PortFeedbackURL.url(kind: "bug").absoluteString == "https://github.com/Roldyy/mac-island/issues/new?labels=bug")
        #expect(PortFeedbackURL.url(kind: "feature").absoluteString.hasSuffix("labels=enhancement"))
        #expect(PortFeedbackURL.url(kind: "x").absoluteString == PortFeedbackURL.issues)
    }

    @Test func showingTheIconSwitchesTheHideOptionOffFirst() {
        PortHostFixture.isolated { defaults in
            let previous = AppDelegate.current
            defer { AppDelegate.current = previous }
            PortBridge.install(host: PortBridge.Host(openSettings: {}))
            defaults.set(true, forKey: DefaultsKey.menuBarHideIconWithMetrics)
            var shown = 0
            PortBridge.connectMenuBar(showIcon: { shown += 1 })
            appDelegate()?.reshowStatusItem()
            #expect(shown == 1)
            #expect(defaults.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics) == false, "or the next sync hides it again")
        }
    }

    @Test func aButtonThatActsOnTheScreenClosesOurIslandFirst() async {
        let previous = AppDelegate.current
        defer { AppDelegate.current = previous }
        PortBridge.install(host: PortBridge.Host(openSettings: {}))
        var closed = 0
        var tabs: [String] = []
        PortBridge.connectIsland(openTab: { tabs.append($0) }, close: { closed += 1 })
        appDelegate()?.openIslandTab(id: "clipboard")
        #expect(tabs == ["clipboard"])

        let ran = Opened()
        NotchService.shared.perform { ran.ids.append("ran") }  // "Choose area" of the Surveillance tab
        #expect(closed == 1)
        let deadline = Date().addingTimeInterval(120)
        while ran.ids.isEmpty, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(ran.ids == ["ran"], "the action still runs, after the island is gone")
    }

    @Test func aLaterConnectKeepsTheDoorsOfAnEarlierOneAcrossInstall() {
        let previous = AppDelegate.current
        defer { AppDelegate.current = previous }
        PortBridge.install(host: PortBridge.Host(openSettings: {}))
        PortBridge.connectIsland(openTab: { _ in }, close: {})
        PortBridge.install(host: PortBridge.Host(openSettings: {}))  // idempotent: the island door survives
        #expect(PortHookCatalog.isBound("openIslandTab", on: AppDelegate.current))
        #expect(PortHookCatalog.isBound("closeIsland", on: AppDelegate.current))
    }
}
