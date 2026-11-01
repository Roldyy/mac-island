import Foundation
import IslandKit
import Testing
@testable import ShellKit

/// The poll can run for as long as a feature is on and its permission is never granted, so its cost is pinned:
/// 2.5 s with timer slack, a STOP after a quiet minute (every reading is a TCC round trip: the 5 s backoff it
/// replaced was a `TCCAccessRequest() IPC` on the main thread every 5 s for ever), and the 1 s burst only after
/// the Accessibility notification. Fakes only: no real timer, no real permission.
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

    @Test func aQuietMinuteStopsThePollForGood() {
        let r = rig()
        for _ in 0..<(PermissionMonitor.quietPollsBeforeIdle - 1) { r.scheduler.fire() }
        #expect(r.scheduler.running, "not yet: one quiet poll short of the stop")
        let readsBefore = r.box.reads
        r.scheduler.fire()
        #expect(!r.scheduler.running && !r.monitor.isPolling, "a minute without a change: no timer at all")
        #expect(r.scheduler.startCount == 1, "never re-rated to a slower poll")
        for _ in 0..<50 { r.scheduler.fire() }   // a stopped scheduler fires nothing
        #expect(r.box.reads == readsBefore + 1, "no reading once idle")
    }

    @Test func idleStaysIdleWhenTheRegistryRefreshesThePolling() {
        let r = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeIdle { r.scheduler.fire() }
        #expect(!r.scheduler.running)
        for _ in 0..<5 { r.monitor.refreshPolling() }   // the registry does this on every switch change
        #expect(!r.scheduler.running && r.scheduler.startCount == 1, "a feature switch is not a reason to poll again")
    }

    @Test func aChangeAnActivationOrAPressStartsThePollAgain() {
        // A change of the answer (another permission arrives while one is still missing).
        let a = rig(needed: [.accessibility, .screenRecording])
        for _ in 0..<(PermissionMonitor.quietPollsBeforeIdle - 1) { a.scheduler.fire() }
        a.box.value = PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: true)
        a.scheduler.fire()
        #expect(a.scheduler.running, "a change resets the quiet count")

        // Coming back from System Settings.
        let b = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeIdle { b.scheduler.fire() }
        #expect(!b.scheduler.running)
        b.triggers.send(.activated)
        #expect(b.scheduler.running && b.scheduler.intervals.last == 2.5)

        // "Revérifier" (the Settings window opening does the same).
        let c = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeIdle { c.scheduler.fire() }
        #expect(!c.scheduler.running)
        c.monitor.recheck()
        #expect(c.scheduler.running && c.scheduler.intervals.last == 2.5)

        // "Autoriser" is followed by the user coming back: the activation restarts it.
        let d = rig()
        for _ in 0..<PermissionMonitor.quietPollsBeforeIdle { d.scheduler.fire() }
        d.monitor.noteOpened(.accessibility)
        d.triggers.send(.activated)
        #expect(d.scheduler.running)
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
        for _ in 0..<(PermissionMonitor.quietPollsBeforeIdle - 1) { r.scheduler.fire() }
        r.box.value = .all
        r.scheduler.fire()
        #expect(!r.monitor.isPolling && !r.scheduler.running)
        r.box.value = .none
        r.triggers.send(.activated)
        #expect(r.scheduler.intervals.last == 2.5, "a later revoke starts again at the base rate")
    }

    // MARK: - Off the main thread

    /// A reading that records which thread ran it.
    final class ThreadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var onMain: [Bool] = []
        private var value: PermissionSnapshot
        init(_ value: PermissionSnapshot) { self.value = value }
        func read() -> PermissionSnapshot {
            lock.lock(); defer { lock.unlock() }
            onMain.append(Thread.isMainThread)
            return value
        }
        func set(_ new: PermissionSnapshot) { lock.lock(); value = new; lock.unlock() }
        var reads: [Bool] { lock.lock(); defer { lock.unlock() }; return onMain }
    }

    @Test func theTimersReadingRunsOffTheMainThreadAndOnlyTheResultComesBack() async {
        let log = ThreadLog(.none)
        let scheduler = FakeScheduler()
        let monitor = PermissionMonitor(read: { .none }, needed: { [.accessibility] }, scheduler: scheduler,
                                        backgroundRead: { log.read() })
        monitor.start()
        scheduler.fire()
        #expect(await waitFor { !log.reads.isEmpty })
        #expect(log.reads == [false], "the probe ran off the main thread")
        // A grant read off the main thread is applied on it and stops the poll (a tick that finds the previous
        // reading still in flight is dropped, so the test keeps ticking until one lands).
        log.set(.all)
        #expect(await waitFor { scheduler.fire(); return !monitor.isPolling })
        #expect(monitor.snapshot == .all)
        #expect(log.reads.allSatisfy { !$0 })
    }

    @Test func aReadingStillInFlightIsNotStartedTwice() async {
        let log = ThreadLog(.none)
        let scheduler = FakeScheduler()
        let monitor = PermissionMonitor(read: { .none }, needed: { [.accessibility] }, scheduler: scheduler,
                                        backgroundRead: { Thread.sleep(forTimeInterval: 0.15); return log.read() })
        monitor.start()
        scheduler.fire()
        scheduler.fire()
        scheduler.fire()
        #expect(await waitFor { log.reads.count >= 1 })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(log.reads.count == 1, "one probe at a time")
        monitor.stop()
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(10)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
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
