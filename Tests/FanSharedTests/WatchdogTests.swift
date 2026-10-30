import Testing
@testable import FanShared

/// `#expect` cannot call mutating members, so each step is captured first.
@Suite struct WatchdogTests {
    @Test func startsDisarmedAndNeverExpiresUntilArmed() {
        var w = Watchdog(timeout: 8)
        #expect(!w.isArmed)
        let expired = w.expired(now: 1_000_000)
        let beat = w.heartbeat(now: 5)   // a heartbeat does not arm it
        #expect(!expired)
        #expect(!beat)
        #expect(!w.isArmed)
    }

    @Test func expiresOnceAfterTheTimeoutWithoutHeartbeat() {
        var w = Watchdog(timeout: 8)
        w.arm(now: 100)
        let early = w.expired(now: 107.9)
        let atDeadline = w.expired(now: 108)
        #expect(!early)
        #expect(atDeadline)
        #expect(!w.isArmed)
        let again = w.expired(now: 200)   // fires once
        #expect(!again)
    }

    @Test func heartbeatsPushTheDeadline() {
        var w = Watchdog(timeout: 8)
        w.arm(now: 100)
        let b1 = w.heartbeat(now: 106)
        let e1 = w.expired(now: 113)
        let b2 = w.heartbeat(now: 113)
        let e2 = w.expired(now: 120.9)
        let e3 = w.expired(now: 121)
        #expect(b1)
        #expect(!e1)
        #expect(b2)
        #expect(!e2)
        #expect(e3)
    }

    @Test func aLateHeartbeatCannotReviveIt() {
        var w = Watchdog(timeout: 8)
        w.arm(now: 100)
        let late = w.heartbeat(now: 108.5)   // after the deadline, before anyone checked
        let expired = w.expired(now: 108.6)
        #expect(!late)
        #expect(expired)
    }

    @Test func disarmStopsIt() {
        var w = Watchdog(timeout: 8)
        w.arm(now: 100)
        w.disarm()
        let expired = w.expired(now: 500)
        let beat = w.heartbeat(now: 101)
        #expect(!expired)
        #expect(!beat)
    }

    @Test func invalidTimeoutsFallBackToTheContractValue() {
        #expect(Watchdog(timeout: .nan).timeout == FanHelperContract.watchdogTimeout)
        #expect(Watchdog(timeout: 0).timeout == FanHelperContract.watchdogTimeout)
        #expect(Watchdog(timeout: -3).timeout == FanHelperContract.watchdogTimeout)
        #expect(Watchdog(timeout: .infinity).timeout == FanHelperContract.watchdogTimeout)
    }

    @Test func nonFiniteNowExpiresRatherThanHanging() {
        var w = Watchdog(timeout: 8)
        w.arm(now: 100)
        let expired = w.expired(now: .nan)
        #expect(expired)
    }
}
