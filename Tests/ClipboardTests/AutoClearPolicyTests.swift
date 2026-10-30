import Testing
@testable import ClipboardFeature

@Suite struct AutoClearPolicyTests {
    @Test func clearsOnlyWhenUnchanged() {
        #expect(AutoClearPolicy.shouldClear(expectedChangeCount: 7, currentChangeCount: 7))
        #expect(!AutoClearPolicy.shouldClear(expectedChangeCount: 7, currentChangeCount: 8))
    }

    @Test func zeroOrNegativeDelayDisables() {
        #expect(AutoClearPolicy.effectiveDelay(0) == nil)
        #expect(AutoClearPolicy.effectiveDelay(-5) == nil)
        #expect(AutoClearPolicy.effectiveDelay(20) == 20)
    }
}
