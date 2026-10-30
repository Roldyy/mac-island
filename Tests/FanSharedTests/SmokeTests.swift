import Testing
@testable import FanShared

@Suite struct FanSharedSmokeTests {
    @Test func labelIsStable() { #expect(FanShared.helperLabel == "be.roldy.macisland.fanhelper") }
}
