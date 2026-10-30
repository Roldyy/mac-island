import Testing
@testable import FansFeature

@Suite struct FansSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(FansFeature.tab().id == "fans")
    }
}
