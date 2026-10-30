import Testing
@testable import FinderFeature

@Suite struct FinderSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(FinderFeature.tab().id == "finder")
    }
}
