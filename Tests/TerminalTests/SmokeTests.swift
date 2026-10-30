import Testing
@testable import TerminalFeature

@Suite struct TerminalSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(TerminalFeature.tab().id == "terminal")
    }
}
