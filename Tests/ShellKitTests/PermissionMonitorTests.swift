import Foundation
import IslandKit
import Testing
@testable import ShellKit

@MainActor final class FakeScheduler: PermissionPollScheduler {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var running = false
    private var tick: (@MainActor () -> Void)?

    func start(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        startCount += 1
        running = true
        self.tick = tick
    }
    func stop() { stopCount += 1; running = false; tick = nil }
    /// One poll, only if the scheduler is running.
    func fire() { tick?() }
}

@MainActor final class FakeTriggers: PermissionTriggerSource {
    private var handler: (@MainActor (PermissionTrigger) -> Void)?
    func install(_ handler: @escaping @MainActor (PermissionTrigger) -> Void) { self.handler = handler }
    func send(_ trigger: PermissionTrigger) { handler?(trigger) }
}

@MainActor final class SnapshotBox {
    var value: PermissionSnapshot
    private(set) var reads = 0
    init(_ value: PermissionSnapshot) { self.value = value }
    func read() -> PermissionSnapshot { reads += 1; return value }
}

extension PermissionSnapshot {
    static let none = PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: false)
    static let all = PermissionSnapshot(accessibility: true, inputMonitoring: true, screenRecording: true)
}

@MainActor
@Suite struct PermissionMonitorTests {
    struct Rig {
        let box: SnapshotBox
        let scheduler: FakeScheduler
        let triggers: FakeTriggers
        let monitor: PermissionMonitor
        let changes: ChangeLog
    }

    final class ChangeLog { var list: [PermissionChange] = [] }

    func rig(_ initial: PermissionSnapshot, needed: Set<MonitoredPermission> = Set(MonitoredPermission.allCases)) -> Rig {
        let box = SnapshotBox(initial)
        let log = ChangeLog()
        let scheduler = FakeScheduler()
        let triggers = FakeTriggers()
        let monitor = PermissionMonitor(read: { box.read() }, needed: { needed }, scheduler: scheduler,
                                        triggers: triggers, onChange: { log.list.append($0) })
        monitor.start()
        return Rig(box: box, scheduler: scheduler, triggers: triggers, monitor: monitor, changes: log)
    }

    // MARK: - Tracker (pure)

    @Test func trackerReportsOnlyRealDifferences() {
        var t = PermissionTracker(initial: .none)
        #expect(t.observe(.none) == nil)
        let change = t.observe(PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false))
        #expect(change?.granted == [.accessibility])
        #expect(change?.revoked == [])
        #expect(t.observe(t.snapshot) == nil)
        #expect(t.observe(.none)?.revoked == [.accessibility])
    }

    @Test func trackerSuspectsAStaleGrantOnlyAfterTheUserCameBack() {
        var t = PermissionTracker(initial: .none)
        t.noteOpened(.screenRecording)
        for _ in 0..<10 { _ = t.observe(.none) }
        #expect(t.staleSuspected.isEmpty, "the pane is still open: nothing to suspect yet")
        t.noteReturned()
        for _ in 0..<(PermissionTracker.staleAfterObservations - 1) { _ = t.observe(.none) }
        #expect(t.staleSuspected.isEmpty)
        _ = t.observe(.none)
        #expect(t.staleSuspected == [.screenRecording])
        _ = t.observe(PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: true))
        #expect(t.staleSuspected.isEmpty, "a real grant clears the suspicion")
    }

    @Test func accessibilityIsNeverSuspectedWhenItWasNotOpened() {
        var t = PermissionTracker(initial: .none)
        t.noteReturned()
        for _ in 0..<10 { _ = t.observe(.none) }
        #expect(t.staleSuspected.isEmpty)
    }

    // MARK: - Monitor

    @Test func nothingPublishedWhenTheAnswerIsUnchanged() {
        let r = rig(.none)
        for _ in 0..<5 { r.monitor.recheck() }
        #expect(r.changes.list.isEmpty)
        #expect(r.monitor.snapshot == .none)
    }

    @Test func aGrantIsPublishedOnceWithItsDifference() {
        let r = rig(.none)
        r.box.value = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false)
        r.monitor.recheck()
        r.monitor.recheck()
        #expect(r.changes.list.count == 1)
        #expect(r.changes.list.first?.granted == [.accessibility])
        #expect(r.monitor.snapshot.accessibility)
    }

    @Test func pollRunsWhileANeededPermissionIsMissingAndStopsOnceGranted() {
        let r = rig(.none, needed: [.accessibility])
        #expect(r.scheduler.running && r.monitor.isPolling)
        r.scheduler.fire()
        #expect(r.scheduler.running)
        r.box.value = .all
        r.scheduler.fire()
        #expect(!r.scheduler.running && !r.monitor.isPolling)
        #expect(r.scheduler.startCount == 1)
    }

    @Test func noPollWhenEverythingNeededIsGrantedOrNothingIsNeeded() {
        #expect(rig(.all).scheduler.startCount == 0)
        #expect(rig(.none, needed: []).scheduler.startCount == 0)
    }

    @Test func revokeRestartsThePollAndGrantStopsIt() {
        let r = rig(.all)
        #expect(!r.monitor.isPolling)
        r.box.value = PermissionSnapshot(accessibility: false, inputMonitoring: true, screenRecording: true)
        r.triggers.send(.activated)
        #expect(r.monitor.isPolling)
        #expect(r.changes.list.last?.revoked == [.accessibility])
    }

    @Test func activationRereadsImmediately() {
        let r = rig(.none)
        let before = r.box.reads
        r.box.value = .all
        r.triggers.send(.activated)
        #expect(r.box.reads == before + 1)
        #expect(r.changes.list.count == 1)
    }

    @Test func accessibilityNotificationPollsAShortBurstEvenWhenGranted() {
        let r = rig(.all)
        r.triggers.send(.accessibilityChanged)
        #expect(r.monitor.isPolling)
        for _ in 0..<PermissionMonitor.burstPolls { r.scheduler.fire() }
        #expect(!r.monitor.isPolling)
    }

    @Test func staleHintAppearsAfterReturningFromAPaneThatChangedNothing() {
        let r = rig(.none)
        r.monitor.noteOpened(.accessibility)
        r.triggers.send(.activated)
        for _ in 0..<PermissionTracker.staleAfterObservations { r.scheduler.fire() }
        #expect(r.monitor.staleSuspected == [.accessibility])
        r.box.value = .all
        r.scheduler.fire()
        #expect(r.monitor.staleSuspected.isEmpty)
    }

    @Test func liveProbeSnapshotNeverPrompts() {
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { false },
                                    inputMonitoring: { true }, automation: { _ in nil })
        #expect(probe.snapshot() == PermissionSnapshot(accessibility: true, inputMonitoring: true, screenRecording: false))
    }
}
