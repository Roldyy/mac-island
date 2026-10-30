import Testing
@testable import CommandBarFeature

@Suite struct CommandBarSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(CommandBarFeature.tab().id == "commandbar")
    }
}
