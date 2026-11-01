import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct ShellLayoutTests {
    @Test func fourFixedGroupsWithTheExpectedSections() {
        #expect(ShellLayout.groups.map(\.title) == ["Terminal", "Presse-papiers", "Lecture", "Moniteur"])
        #expect(ShellLayout.groups.map { $0.sections.map(\.id) } == [
            ["terminal", "agents"], ["clipboard", "shelf"], ["nowplaying", "audio", "keepawake"], ["monitor", "fans"],
        ])
    }

    @Test func everySectionIsARegisteredFeatureAndNoneIsListedTwice() {
        let ids = ShellLayout.groups.flatMap { $0.sections.map(\.id) }
        #expect(Set(ids).count == ids.count)
        let known = Set(ShellDescriptors.all.map(\.id))
        #expect(ids.allSatisfy(known.contains))
    }

    @Test func tabsOutsideGroupsAreTheFourSettingsOnlyOnes() {
        let outside = ShellLayout.tabsOutsideGroups(ShellDescriptors.all.compactMap(\.tabID))
        #expect(Set(outside) == ["commandbar", "finder", "dock", "display"])
    }

    @Test func descriptorIdsAreUniqueAndTabIdsMatch() {
        let ids = ShellDescriptors.all.map(\.id)
        #expect(ids.count == 13 && Set(ids).count == 13)
        #expect(ShellDescriptors.all.allSatisfy { $0.tabID == $0.id })
    }

    @Test func resolvedSectionFallsBackToFirstVisible() {
        let g = ShellLayout.groups[2]
        let visible = ShellLayout.visibleSections(of: g) { $0 != "nowplaying" }
        #expect(ShellLayout.resolvedSection(remembered: "audio", visible: visible) == "audio")
        #expect(ShellLayout.resolvedSection(remembered: "nowplaying", visible: visible) == "audio")
        #expect(ShellLayout.resolvedSection(remembered: nil, visible: visible) == "audio")
        #expect(ShellLayout.resolvedSection(remembered: "audio", visible: []) == nil)
    }

    @Test func navigationJumpsToAnySectionOfAGroup() {
        let nav = ShellNavigation()
        #expect(nav.select(tabID: "fans"))
        #expect(nav.selectedGroup == "monitor" && nav.sections["monitor"] == "fans")
        #expect(!nav.select(tabID: "dock"))
        #expect(nav.selectedGroup == "monitor")
    }
}

@MainActor
@Suite struct QuickAccessTests {
    @Test func defaultsAreTheSixExpectedButtons() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let m = QuickAccessModel(defaults: b.defaults)
        #expect(m.items.map(\.title) == ["Commandes", "Capture", "Verrouiller l'écran", "Mode nettoyage", "Éveil", "Réglages"])
    }

    @Test func sanitizingDropsUnknownDuplicatesAndExtras() {
        #expect(QuickAccessCatalog.sanitized(["settings", "bogus", "settings", "capture"]) == ["settings", "capture"])
        #expect(QuickAccessCatalog.sanitized([]) == QuickAccessCatalog.defaultIDs)
        #expect(QuickAccessCatalog.sanitized(["bogus"]) == QuickAccessCatalog.defaultIDs)
        #expect(QuickAccessCatalog.sanitized(QuickAccessCatalog.defaultIDs + ["settings"]).count == 6)
    }

    @Test func configuredListPersists() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        QuickAccessModel(defaults: b.defaults).setIDs(["keepawake", "settings"])
        #expect(QuickAccessModel(defaults: b.defaults).ids == ["keepawake", "settings"])
    }

    @Test func tableFiresRegisteredActionsOnly() {
        let t = QuickActionTable()
        var fired = 0
        #expect(!t.isAvailable("settings") && !t.fire("settings"))
        t.register("settings") { fired += 1 }
        #expect(t.isAvailable("settings") && t.fire("settings"))
        #expect(fired == 1)
    }
}

@Suite struct FeatureHubTests {
    @Test func groupsByCategoryInEnumOrderAndSkipsEmptyOnes() {
        let sections = FeatureHub.sections(ShellDescriptors.all, query: "")
        #expect(sections.map(\.category) == [.daily, .claude, .display, .sound, .windows, .monitor, .files, .tools, .media])
        #expect(sections.flatMap(\.features).count == 13)
    }

    @Test func searchIgnoresCaseAndAccentsAndMatchesSummaryAndCategory() {
        func ids(_ q: String) -> [String] { FeatureHub.sections(ShellDescriptors.all, query: q).flatMap(\.features).map(\.id) }
        #expect(ids("etagere") == ["shelf"])
        #expect(ids("PRESSE") == ["clipboard"])
        #expect(ids("surveillance") == ["monitor", "fans"])
        #expect(ids("inactives") == ["display"], "the Display tab is auto-quit now: brightness is the ported feature")
        #expect(ids("luminosite").isEmpty)
        #expect(ids("zzzz").isEmpty)
    }

    @Test func everyStateHasAFrenchBadge() {
        #expect(FeatureBadge(.active).text == "Prêt")
        #expect(FeatureBadge(.needsPermission(.accessibility)).text == "Autorisation requise : Accessibilité")
        #expect(FeatureBadge(.needsPermission(.accessibility)).status == .warning)
        #expect(FeatureBadge(.quarantined).status == .danger)
        #expect(FeatureBadge(.off).text == "Désactivé")
    }

    @Test func everyPermissionHasAPaneAndATitle() {
        for p in FeaturePermission.allCases {
            #expect(p.settingsURL != nil, "\(p)")
            #expect(!p.title.isEmpty)
        }
    }
}
