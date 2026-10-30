import Testing
@testable import TerminalFeature

@Suite struct TerminalSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(TerminalFeature.tab().id == "terminal")
    }
}

@Suite struct TerminalTabTests {
    @Test @MainActor func tabMetadata() {
        let tab = TerminalFeature.tab()
        #expect(tab.title == "Terminal")
        #expect(tab.systemImage == "terminal")
    }

    @Test func pillHidesWhenIdle() {
        #expect(ClaudeStatusPill.Style(.idle) == nil)
        #expect(ClaudeStatusPill.Style(.working)?.label == "Travaille")
        #expect(ClaudeStatusPill.Style(.waiting)?.label == "Attend")
        #expect(ClaudeStatusPill.Style(.done)?.label == "Terminé")
    }
}
