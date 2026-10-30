import Testing
@testable import MonitorFeature

@Suite struct MonitorSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(MonitorFeature.tab().id == "monitor")
    }
}
