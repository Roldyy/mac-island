import Foundation
import Testing
@testable import FanShared

@Suite struct LogThrottleTests {
    /// `allow` is mutating, which `#expect` cannot call directly: collect the answers first.
    private func answers(_ throttle: inout LogThrottle, at times: [TimeInterval]) -> [Bool] {
        times.map { throttle.allow(now: $0) }
    }

    @Test func letsTheFirstEventThroughThenOncePerInterval() {
        var t = LogThrottle(interval: 10)
        #expect(answers(&t, at: [100, 101, 109.9, 110, 111]) == [true, false, false, true, false])
    }

    @Test func resetLetsTheNextEventThrough() {
        var t = LogThrottle(interval: 10)
        #expect(answers(&t, at: [100]) == [true])
        t.reset()
        #expect(answers(&t, at: [101, 102]) == [true, false])
    }

    @Test func aClockThatWentBackwardsNeverSilencesItForever() {
        var t = LogThrottle(interval: 10)
        #expect(answers(&t, at: [100, 50, 51]) == [true, true, false])
    }
}
