import Testing
@testable import ClipboardFeature

@Suite struct AutoClearPolicyTests {
    @Test func clearsOnlyWhenNothingNewWasCopied() {
        // Behaviour, not a restatement of the implementation: a later copy bumps the count.
        var count = 7
        let expected = count
        #expect(AutoClearPolicy.shouldClear(expectedChangeCount: expected, currentChangeCount: count))
        count += 1
        #expect(!AutoClearPolicy.shouldClear(expectedChangeCount: expected, currentChangeCount: count))
        count -= 2   // never clear a pasteboard whose count is not the one we scheduled for
        #expect(!AutoClearPolicy.shouldClear(expectedChangeCount: expected, currentChangeCount: count))
    }

    @Test func zeroOrNegativeDelayDisables() {
        #expect(AutoClearPolicy.effectiveDelay(0) == nil)
        #expect(AutoClearPolicy.effectiveDelay(-5) == nil)
        #expect(AutoClearPolicy.effectiveDelay(20) == 20)
    }
}
