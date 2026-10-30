import Testing
@testable import ShelfFeature

@Suite struct ShelfSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(ShelfFeature.tab().id == "shelf")
    }
}
