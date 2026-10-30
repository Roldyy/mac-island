import Testing
@testable import FansFeature

@Suite struct FansSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        let tab = FansFeature.tab()
        #expect(tab.id == "fans")
        #expect(tab.title == "Ventilos")
        #expect(tab.systemImage == "fan")
    }
}
