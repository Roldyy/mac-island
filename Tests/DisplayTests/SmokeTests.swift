import Testing
@testable import DisplayFeature

@Suite struct DisplaySmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(DisplayFeature.tab().id == "display")
    }
}
