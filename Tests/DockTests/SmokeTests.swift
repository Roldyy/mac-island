import Testing
@testable import DockFeature

@Suite struct DockSmokeTests {
    /// The Home tile, the command bar, the Settings pages and the migrated switch all reach the Dock through the tab id `dock`.
    @Test @MainActor func tabHasStableIdentity() {
        let tab = DockFeature.tab()
        #expect(tab.id == "dock")
        #expect(tab.title == "Dock")
        #expect(tab.systemImage == "dock.rectangle")
    }
}
