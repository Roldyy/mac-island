import Foundation
import IslandKit
import Testing
@testable import ShellKit

/// The poll can run for as long as a feature is on and its permission is never granted, so its cost is pinned:
/// 2.5 s with timer slack, a backoff after a quiet minute, and the 1 s burst only after the Accessibility
/// notification. Fakes only: no real timer, no real permission.
@MainActor
@Suite struct PermissionPollCostTests {
    func rig(_ initial: PermissionSnapshot = .none, needed: Set<MonitoredPermission> = [.accessibility])
        -> (box: SnapshotBox, scheduler: FakeScheduler, triggers: FakeTriggers, monitor: PermissionMonitor) {
        let box = SnapshotBox(initial)
        let scheduler = FakeScheduler()
        let triggers = FakeTriggers()
        let monitor = PermissionMonitor(read: { box.read() }, needed: { needed }, scheduler: scheduler, triggers: triggers)
        monitor.start()
        return (box, scheduler, triggers, monitor)
    }

    @Test func baseRateIsTwoAndAHalfSecondsWithOneSecondOfSlack() {
        #expect(PermissionMonitor.pollInterval == 2.5)
        #expect(PermissionMonitor.pollTolerance == 1)
        let r = rig()
        #expect(r.scheduler.intervals == [2.5])
        #expect(r.scheduler.tolerances == [1])
    }

    @Test func aQuietMinuteBacksOffToFiveSeconds() {
        let r = rig()
        for _ in 0..<(PermissionMonitor.quietPollsBeforeBackoff - 1) { r.scheduler.fire() }
        #expect(r.scheduler.intervals == [2.5], "not yet: one quiet poll short of the backoff")
        r.scheduler.fire()
        #expect(r.scheduler.intervals == [2.5, 5])
        #expect(r.scheduler.tolerances.last == 2)
        for _ in 0..<50 { r.scheduler.fire() }
        #expect(r.scheduler.startCount == 2, "once backed off, the timer is left alone")
        #expect(r.monitor.isPolling)
    }

    @Test func aChangeAnActivationOrAPressPutsThePollBackToTheBaseRate() {
        // A change of the answer (another permission arrives while one is still missing).
        let a = rig(needed: [.accessibility, .screenRecording])
        for _ in 0..<PermissionMonitor.quietPollsBeforeBackoff { a.scheduler.fire() }
        #expect(a.scheduler.intervals.last == 5)
        a.box.value = PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: true)
        a.scheduler.fire()
        #expect(a.scheduler.intervals.last == 2.5)

        // Coming back from System Settings.
        let b = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeBackoff { b.scheduler.fire() }
        #expect(b.scheduler.intervals.last == 5)
        b.triggers.send(.activated)
        #expect(b.scheduler.intervals.last == 2.5)

        // "Revérifier".
        let c = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeBackoff { c.scheduler.fire() }
        c.monitor.recheck()
        #expect(c.scheduler.intervals.last == 2.5)

        // "Autoriser".
        let d = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeBackoff { d.scheduler.fire() }
        d.monitor.noteOpened(.accessibility)
        d.scheduler.fire()
        #expect(d.scheduler.intervals.last == 2.5)
    }

    @Test func theAccessibilityNotificationKeepsItsOneSecondBurstThenReturnsToTheBaseRate() {
        let r = rig()
        r.triggers.send(.accessibilityChanged)
        #expect(r.scheduler.intervals == [2.5, 1], "the burst re-rates the running poll")
        #expect(r.scheduler.tolerances.last == 0.1)
        for _ in 0..<PermissionMonitor.burstPolls { r.scheduler.fire() }
        #expect(r.scheduler.intervals == [2.5, 1, 2.5], "back to the base rate once the burst is spent")
        #expect(r.monitor.isPolling, "the permission is still missing")
    }

    @Test func aGrantedPermissionStopsThePollWhateverTheRate() {
        let r = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeBackoff { r.scheduler.fire() }
        r.box.value = .all
        r.scheduler.fire()
        #expect(!r.monitor.isPolling && !r.scheduler.running)
        r.box.value = .none
        r.triggers.send(.activated)
        #expect(r.scheduler.intervals.last == 2.5, "a later revoke starts again at the base rate")
    }

    @Test func snapshotObserversGetTheCurrentReadingThenEveryChangeBeforeTheRegistry() {
        let box = SnapshotBox(.none)
        let scheduler = FakeScheduler()
        let log = ChangeOrder()
        let monitor = PermissionMonitor(read: { box.read() }, needed: { [] }, scheduler: scheduler, triggers: nil,
                                        onChange: { _ in log.events.append("registry") })
        monitor.addSnapshotObserver { log.events.append("observer ax=\($0.accessibility)") }
        #expect(log.events == ["observer ax=false"], "called at once with the current reading")
        box.value = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false)
        monitor.recheck()
        monitor.recheck()
        #expect(log.events == ["observer ax=false", "observer ax=true", "registry"], "once, observer first")
    }

    final class ChangeOrder { var events: [String] = [] }
}
