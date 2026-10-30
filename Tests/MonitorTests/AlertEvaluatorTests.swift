import Foundation
import Testing
@testable import MonitorFeature

@Suite struct AlertEvaluatorTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let rule = AlertRule(threshold: 90, sustained: 30, cooldown: 900, clearMargin: 5)

    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func belowThresholdNeverAlerts() {
        var e = AlertEvaluator()
        for s in stride(from: 0.0, through: 600, by: 5) {
            #expect(e.evaluate(.cpu, value: 89.9, rule: rule, now: at(s)) == nil)
        }
        #expect(!e.isActive(.cpu))
    }

    @Test func raisesOnlyOnceSustained() {
        var e = AlertEvaluator()
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(0)) == nil)
        #expect(e.evaluate(.cpu, value: 96, rule: rule, now: at(29)) == nil)
        #expect(e.evaluate(.cpu, value: 97, rule: rule, now: at(30)) == .raised(.cpu, 97))
        #expect(e.isActive(.cpu))
    }

    @Test func valueEqualToThresholdCountsAsAbove() {
        var e = AlertEvaluator()
        _ = e.evaluate(.memory, value: 90, rule: rule, now: at(0))
        #expect(e.evaluate(.memory, value: 90, rule: rule, now: at(30)) == .raised(.memory, 90))
    }

    @Test func dipBeforeSustainedRestartsTheTimer() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        #expect(e.evaluate(.cpu, value: 50, rule: rule, now: at(20)) == nil)
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(25))
        // 30 s after the first spike but only 25 s after the restart.
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(50)) == nil)
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(55)) == .raised(.cpu, 95))
    }

    @Test func noRepeatWhileStillAbove() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(30))
        for s in stride(from: 35.0, through: 3600, by: 5) {
            #expect(e.evaluate(.cpu, value: 99, rule: rule, now: at(s)) == nil)
        }
    }

    @Test func staysActiveInsideTheHysteresisBand() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(30))
        #expect(e.evaluate(.cpu, value: 86, rule: rule, now: at(40)) == nil)  // 85 < 86 < 90
        #expect(e.isActive(.cpu))
        #expect(e.evaluate(.cpu, value: 84.9, rule: rule, now: at(45)) == .cleared(.cpu))
        #expect(!e.isActive(.cpu))
    }

    @Test func clearedEmitsOnce() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(30))
        #expect(e.evaluate(.cpu, value: 10, rule: rule, now: at(35)) == .cleared(.cpu))
        #expect(e.evaluate(.cpu, value: 10, rule: rule, now: at(40)) == nil)
    }

    @Test func noReRaiseInsideCooldownThenRaisesWhenItEnds() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(30)) == .raised(.cpu, 95))
        #expect(e.evaluate(.cpu, value: 10, rule: rule, now: at(60)) == .cleared(.cpu))
        // High again from t=120, sustained since t=150, but the raise was at t=30: cool-down to t=930.
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(120))
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(150)) == nil)
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(929)) == nil)
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(930)) == .raised(.cpu, 95))
    }

    @Test func dropDuringCooldownWaitCancelsThePendingRaise() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(30))
        _ = e.evaluate(.cpu, value: 10, rule: rule, now: at(60))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(120))
        _ = e.evaluate(.cpu, value: 20, rule: rule, now: at(500))
        // Went back to normal: the cool-down ending at t=930 must not raise a stale alert.
        #expect(e.evaluate(.cpu, value: 20, rule: rule, now: at(940)) == nil)
    }

    @Test func flappingSignalNeverRaises() {
        var e = AlertEvaluator()
        var events = 0
        var s = 0.0
        while s < 900 {
            let v = Int(s / 5) % 2 == 0 ? 97.0 : 40.0
            if e.evaluate(.cpu, value: v, rule: rule, now: at(s)) != nil { events += 1 }
            s += 5
        }
        #expect(events == 0)
    }

    @Test func flappingAroundTheThresholdWhileActiveEmitsNothing() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(30))
        var events = 0
        var s = 35.0
        while s < 900 {
            let v = Int(s / 5) % 2 == 0 ? 91.0 : 88.0
            if e.evaluate(.cpu, value: v, rule: rule, now: at(s)) != nil { events += 1 }
            s += 5
        }
        #expect(events == 0)
        #expect(e.isActive(.cpu))
    }

    @Test func flappingAcrossTheClearLevelClearsOnceAndCooldownBlocksTheRest() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(30))
        var raised = 0, cleared = 0
        var s = 35.0
        while s < 800 {
            let v = Int(s / 5) % 2 == 0 ? 95.0 : 50.0
            switch e.evaluate(.cpu, value: v, rule: rule, now: at(s)) {
            case .raised: raised += 1
            case .cleared: cleared += 1
            case nil: break
            }
            s += 5
        }
        #expect(raised == 0)
        #expect(cleared == 1)
    }

    @Test func zeroSustainedRaisesImmediately() {
        var e = AlertEvaluator()
        let r = AlertRule(threshold: 80, sustained: 0, cooldown: 60, clearMargin: 5)
        #expect(e.evaluate(.cpu, value: 81, rule: r, now: at(0)) == .raised(.cpu, 81))
    }

    @Test func metricsAreIndependent() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.memory, value: 10, rule: rule, now: at(0))
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(30)) == .raised(.cpu, 95))
        #expect(e.evaluate(.memory, value: 10, rule: rule, now: at(30)) == nil)
        #expect(!e.isActive(.memory))
    }

    @Test func resetForgetsEverythingIncludingCooldown() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(0))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(30))
        e.reset()
        #expect(!e.isActive(.cpu))
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(40))
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(70)) == .raised(.cpu, 95))
    }

    @Test func clockGoingBackwardsDoesNotRaise() {
        var e = AlertEvaluator()
        _ = e.evaluate(.cpu, value: 95, rule: rule, now: at(100))
        #expect(e.evaluate(.cpu, value: 95, rule: rule, now: at(0)) == nil)
    }
}
