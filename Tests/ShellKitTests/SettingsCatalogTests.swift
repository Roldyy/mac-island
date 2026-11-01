import Foundation
import Testing
@testable import ShellKit

@Suite struct SettingsCatalogTests {
    @Test func hasSixtyEightPagesInNineSections() {
        #expect(SettingsPageCatalog.all.count == 68)
        #expect(SettingsSection.allCases.count == 9)
        #expect(SettingsSearch.sections(SettingsPageCatalog.all).count == 9)
        #expect(Set(SettingsPageCatalog.all.map(\.id)).count == 68)
    }

    @Test func sectionSizesFollowTheReferenceIndex() {
        let sizes = SettingsSection.allCases.map { SettingsPageCatalog.pages(in: $0).count }
        #expect(sizes == [6, 12, 5, 4, 7, 14, 7, 7, 6])
    }

    @Test func everyPageHasTextAndSymbol() {
        for page in SettingsPageCatalog.all {
            #expect(!page.title.isEmpty && !page.symbol.isEmpty && !page.summary.isEmpty, "\(page.id)")
            #expect(!page.title.contains("Vorssaint") && !page.summary.contains("Vorssaint"))
        }
    }

    @Test func everyContentKeyIsAKnownPage() {
        let ids = Set(SettingsPageCatalog.all.map(\.id))
        #expect(SettingsPageContent.all.keys.allSatisfy(ids.contains))
        #expect(SettingsLive.table.keys.allSatisfy(ids.contains))
    }

    @Test func searchIgnoresCaseAndAccents() {
        let hits = SettingsSearch.filter(SettingsPageCatalog.all, query: "ETAGERE").map(\.id)
        #expect(hits.first == "shelf")
        #expect(SettingsSearch.filter(SettingsPageCatalog.all, query: "").count == 68)
        #expect(SettingsSearch.filter(SettingsPageCatalog.all, query: "zzzzqq").isEmpty)
    }

    @Test func titleMatchBeatsKeywordMatch() {
        let hits = SettingsSearch.filter(SettingsPageCatalog.all, query: "dock").map(\.id)
        #expect(hits.prefix(2).contains("dockpreview"))
        #expect(hits.contains("dockclicks"))
    }

    @Test func keywordsFindPages() {
        #expect(SettingsSearch.filter(SettingsPageCatalog.all, query: "veille").map(\.id).contains("keepawake"))
    }
}
