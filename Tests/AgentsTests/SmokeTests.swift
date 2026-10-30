import Testing
@testable import AgentsFeature

@Suite struct AgentsSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(AgentsFeature.tab().id == "agents")
    }
}
