import Testing
@testable import DockFeature

@Suite struct DockSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(DockFeature.tab().id == "dock")
    }
}
