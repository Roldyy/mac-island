import Foundation
import Testing
@testable import KeepAwakeFeature

@Suite struct JiggleSchedulerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func neverWhenInactiveOrDisabled() {
        let s = JiggleScheduler(intervalMinutes: 1)
        #expect(!s.shouldJiggle(now: t0, idleSeconds: 600, keepAwakeActive: false, enabled: true))
        #expect(!s.shouldJiggle(now: t0, idleSeconds: 600, keepAwakeActive: true, enabled: false))
    }

    @Test func onlyWhenIdleForTheInterval() {
        let s = JiggleScheduler(intervalMinutes: 2)
        #expect(!s.shouldJiggle(now: t0, idleSeconds: 119, keepAwakeActive: true, enabled: true))
        #expect(s.shouldJiggle(now: t0, idleSeconds: 120, keepAwakeActive: true, enabled: true))
    }

    @Test func doesNotRepeatBeforeAnotherInterval() {
        var s = JiggleScheduler(intervalMinutes: 1)
        #expect(s.shouldJiggle(now: t0, idleSeconds: 90, keepAwakeActive: true, enabled: true))
        s.didJiggle(at: t0)
        #expect(!s.shouldJiggle(now: t0.addingTimeInterval(30), idleSeconds: 90, keepAwakeActive: true, enabled: true))
        #expect(s.shouldJiggle(now: t0.addingTimeInterval(60), idleSeconds: 90, keepAwakeActive: true, enabled: true))
    }

    @Test func intervalIsClampedToAtLeastOneMinute() {
        let s = JiggleScheduler(intervalMinutes: 0)
        #expect(s.interval == 60)
    }

    @Test func resetForgetsLastJiggle() {
        var s = JiggleScheduler(intervalMinutes: 1)
        s.didJiggle(at: t0)
        s.reset()
        #expect(s.shouldJiggle(now: t0, idleSeconds: 90, keepAwakeActive: true, enabled: true))
    }
}
