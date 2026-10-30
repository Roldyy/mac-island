import Testing
@testable import KeepAwakeFeature

@Suite struct KeepAwakeSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(KeepAwakeFeature.tab().id == "keepawake")
    }
}
