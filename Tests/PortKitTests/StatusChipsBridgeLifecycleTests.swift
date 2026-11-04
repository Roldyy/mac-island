import Combine
import Foundation
import ShellKit
import Testing
@testable import PortKit

/// MIS_0102: the five sources and the temperature lease driven by fakes. Nothing reads hardware, EventKit or a
/// process, nothing is killed, and every start is checked against its stop: no reference, listener or task survives.
@MainActor
@Suite struct StatusChipsBridgeLifecycleTests {
    // MARK: Fakes

    /// A sleep that waits until its task is cancelled (the poller of a started source).
    private static let parked: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }


    /// Lets the main actor run the tasks a call just scheduled.
    private func settle() async { for _ in 0..<30 { await Task.yield() } }

    /// Waits (up to 2 s) for a condition that a task running off the main actor makes true.
    private func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// A short real pause, for "nothing else happens" checks after a stop.
    private func pause() async { try? await Task.sleep(for: .milliseconds(80)) }

    /// Counts what a watch subscribed and what it released.
    private final class Watch<Value> : @unchecked Sendable {
        var subscribed = 0
        var cancelled = 0
        var deliver: (@MainActor (Value) -> Void)?

        func make(_ deliver: @escaping @MainActor (Value) -> Void) -> AnyCancellable? {
            subscribed += 1
            self.deliver = deliver
            return AnyCancellable { [self] in cancelled += 1; self.deliver = nil }
        }
        var active: Int { subscribed - cancelled }
    }

    // MARK: Contract shared by every source

    @Test func facadeBuildsOneIdleSourcePerKind() {
        let sources = PortStatusChips.sources()
        #expect(sources.map(\.kind) == [.batteryHealth, .nextEvent, .topApp, .devices, .timer])
        #expect(Set(sources.map(\.kind)).count == 5)
        #expect(sources.allSatisfy { $0.reading == nil })
    }

    // MARK: Battery health

    @Test func batterySamplesOnStartThenOnlyOnItsCadenceAndNeverAfterStop() async {
        var reads = 0
        let sleeps = Counter()
        let source = BatteryHealthChipSource(
            interval: .seconds(60),
            sleep: { _ in if sleeps.bump() > 2 { try await Task.sleep(for: .seconds(3600)) } },
            navigator: StatusChipNavigator(isAvailable: { true }, open: { _ in }),
            read: { reads += 1; return BatteryHealthSample(healthPercent: 90, cycleCount: 10, externalConnected: true) })
        var changes = 0
        source.onChange = { changes += 1 }
        #expect(reads == 0)
        #expect(source.reading == nil)
        source.start()
        #expect(reads == 1)
        #expect(source.reading?.primary == "90 % santé")
        #expect(source.reading?.actions.map(\.title) == ["Ouvrir le Moniteur"])
        await until { reads == 3 }
        await pause()
        #expect(reads == 3)   // the start plus two cadence ticks, then the fake parks the poller
        #expect(changes == 1) // same reading each time: the feed redraws once
        source.stop()
        #expect(source.reading == nil)
        let afterStop = reads
        await pause()
        #expect(reads == afterStop)
    }

    @Test func batteryStartAndStopAreIdempotent() async {
        var reads = 0
        let source = BatteryHealthChipSource(sleep: Self.parked, navigator: StatusChipNavigator(isAvailable: { false }, open: { _ in }),
                                             read: { reads += 1; return BatteryHealthSample(healthPercent: 85) })
        source.start(); source.start()
        #expect(reads == 1)
        #expect(source.reading?.actions.isEmpty == true)  // the Monitor tab is not reachable: no dead button
        source.stop(); source.stop()
        #expect(source.reading == nil)
    }

    @Test func batteryWithoutABatteryGivesNoChip() {
        let source = BatteryHealthChipSource(sleep: Self.parked, read: { nil })
        source.start()
        #expect(source.reading == nil)
        source.stop()
    }

    // MARK: Next event

    private func nextEventHooks(_ watch: Watch<[NotchCalendarEvent]>, now: @escaping @MainActor () -> Date,
                                sleeps: Counter? = nil,
                                open: @escaping @MainActor (URL) -> Void = { _ in }) -> NextEventChipSource.Hooks {
        NextEventChipSource.Hooks(watch: { watch.make($0) }, now: now,
                                  sleep: { _ in sleeps?.bump(); try await Task.sleep(for: .seconds(3600)) },
                                  openURL: open, openCalendar: {})
    }

    private func event(startsIn: TimeInterval, now: Date, join: URL? = nil) -> NotchCalendarEvent {
        NotchCalendarEvent(id: "e", title: "Revue", calendar: "Travail", start: now.addingTimeInterval(startsIn),
                           end: now.addingTimeInterval(startsIn + 1800), allDay: false, location: "", joinURL: join)
    }

    @Test func nextEventListensOnlyBetweenStartAndStop() async throws {
        // Midday UTC keeps +20 min on the same day in any time zone near it.
        let now = Date(timeIntervalSince1970: 1_793_790_000)
        let watch = Watch<[NotchCalendarEvent]>()
        let wakes = Counter()
        let source = NextEventChipSource(hooks: nextEventHooks(watch, now: { now }, sleeps: wakes))
        #expect(watch.subscribed == 0)
        source.start()
        #expect(watch.active == 1)
        watch.deliver?([event(startsIn: 1200, now: now)])
        #expect(source.reading?.primary == "Revue dans 20 min")
        await until { wakes.value == 1 }
        #expect(wakes.value == 1)   // one wake-up at the next minute roll-over
        watch.deliver?([])
        #expect(source.reading == nil)
        source.stop()
        #expect(watch.active == 0)
        #expect(source.reading == nil)
    }

    @Test func nextEventDropsLateDeliveriesAfterStop() {
        let now = Date(timeIntervalSince1970: 1_793_790_000)
        let watch = Watch<[NotchCalendarEvent]>()
        let source = NextEventChipSource(hooks: nextEventHooks(watch, now: { now }))
        source.start()
        let deliver = watch.deliver
        source.stop()
        deliver?([event(startsIn: 600, now: now)])
        #expect(source.reading == nil)
    }

    @Test func nextEventJoinActionOpensOnlyAValidatedLink() throws {
        let now = Date(timeIntervalSince1970: 1_793_790_000)
        let watch = Watch<[NotchCalendarEvent]>()
        var opened: [URL] = []
        let source = NextEventChipSource(hooks: nextEventHooks(watch, now: { now }, open: { opened.append($0) }))
        source.start()
        let link = try #require(URL(string: "https://teams.microsoft.com/l/meetup-join/abc"))
        watch.deliver?([event(startsIn: 600, now: now, join: link)])
        let join = try #require(source.reading?.actions.first { $0.id == "join" })
        join.handler()
        #expect(opened == [link])
        source.stop()
    }

    // MARK: Top app

    private func topAppHooks(canKill: Bool = true, regular: Bool = true, bundleID: String? = "com.apple.Safari",
                             protected: Bool = false, ownPID: Int32 = 42, quits: Quits = Quits(),
                             rows: @escaping @Sendable () -> [ProcessUsage] = { [] }) -> TopAppChipSource.Hooks {
        TopAppChipSource.Hooks(
            read: rows,
            appInfo: { _ in TopAppRunningInfo(bundleID: bundleID, isRegularApp: regular) },
            ownPID: ownPID, ownBundleID: "be.roldy.macisland",
            canKill: { canKill }, isProtected: { _, _ in protected },
            quit: { quits.calls.append(Quit(pid: $0, name: $1, startedAt: $2)) },
            sleep: Self.parked)
    }

    private struct Quit: Equatable { var pid: pid_t; var name: String; var startedAt: UInt64 }
    private final class Quits : @unchecked Sendable { var calls: [Quit] = [] }

    private func row(_ name: String, pid: pid_t = 500, value: Double = 70, startedAt: UInt64? = 1_234) -> ProcessUsage {
        ProcessUsage(pid: pid, name: name, value: value, startedAt: startedAt)
    }

    @Test func topAppQuitIsFlaggedDestructiveAndRunsWithoutForce() throws {
        let quits = Quits()
        let source = TopAppChipSource(hooks: topAppHooks(quits: quits))
        source.start()
        source.apply([row("Slack", value: 20), row("Safari", value: 72)])
        let reading = try #require(source.reading)
        #expect(reading.primary == "Safari 72 % CPU")
        #expect(reading.level == .attention)
        let quit = try #require(reading.actions.first)
        #expect(quit.title == "Quitter")
        #expect(quit.isDestructive)
        #expect(quit.needsConfirmation)
        #expect(quits.calls.isEmpty)   // building the chip kills nothing
        quit.handler()
        #expect(quits.calls == [Quit(pid: 500, name: "Safari", startedAt: 1_234)])
        source.stop()
    }

    @Test(arguments: ["Finder", "Dock", "loginwindow", "WindowServer", "SystemUIServer", "kernel_task", "ControlCenter", "Mac Island"])
    func topAppHasNoQuitActionForRefusedApps(name: String) throws {
        let quits = Quits()
        let source = TopAppChipSource(hooks: topAppHooks(quits: quits))
        source.start()
        source.apply([row(name, value: 95)])
        let reading = try #require(source.reading)
        #expect(reading.actions.isEmpty)
        #expect(reading.level == .alert)
        #expect(quits.calls.isEmpty)
        source.stop()
    }

    @Test func topAppHasNoQuitActionForOwnProcessBundleOrUnsafeRows() throws {
        func actions(_ hooks: TopAppChipSource.Hooks, _ top: ProcessUsage = ProcessUsage(pid: 500, name: "Safari", value: 70, startedAt: 9)) -> Int {
            let source = TopAppChipSource(hooks: hooks)
            source.start()
            source.apply([top])
            defer { source.stop() }
            return source.reading?.actions.count ?? -1
        }
        #expect(actions(topAppHooks()) == 1)
        #expect(actions(topAppHooks(ownPID: 500)) == 0)                       // Mac Island's own pid
        #expect(actions(topAppHooks(bundleID: "be.roldy.macisland")) == 0)     // its bundle id, any name
        #expect(actions(topAppHooks(protected: true)) == 0)                    // KillProcessService's protected list
        #expect(actions(topAppHooks(regular: false)) == 0)                     // a daemon, not an app
        #expect(actions(topAppHooks(canKill: false)) == 0)                     // Kill Process feature off
        #expect(actions(topAppHooks(), ProcessUsage(pid: 500, name: "Safari", value: 70)) == 0)   // no start time
    }

    @Test func topAppPollsOnlyBetweenStartAndStop() async {
        let reads = Counter()
        let source = TopAppChipSource(hooks: topAppHooks(rows: { reads.bump(); return [ProcessUsage(pid: 500, name: "Safari", value: 12, startedAt: 1)] }))
        #expect(reads.value == 0)
        source.start()
        await until { source.reading != nil }
        #expect(reads.value == 1)   // one read, then the poller parks on its cadence
        #expect(source.reading?.primary == "Safari 12 % CPU")
        source.stop()
        #expect(source.reading == nil)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        @discardableResult func bump() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    @Test func topAppWithNoRowGivesNoChip() {
        let source = TopAppChipSource(hooks: topAppHooks())
        source.start()
        source.apply([])
        #expect(source.reading == nil)
        source.stop()
    }

    // MARK: Devices

    private final class Monitor : @unchecked Sendable {
        var ownedElsewhere = false
        var calls: [Bool] = []
        var control: AccessoryMonitorControl {
            AccessoryMonitorControl(isOwnedElsewhere: { self.ownedElsewhere }, setMonitoring: { self.calls.append($0) })
        }
    }

    private func devicesSource(_ watch: Watch<PeripheralBatterySample>, _ monitor: Monitor) -> DevicesChipSource {
        DevicesChipSource(hooks: .init(watch: { watch.make($0) }, uptime: { 1000 }), monitor: monitor.control)
    }

    private func sample(_ devices: [(String, String, Int)]) -> PeripheralBatterySample {
        PeripheralBatterySample(
            devices: devices.map { PeripheralBatteryDevice(id: $0.0, name: $0.1, percent: $0.2, kind: .audio) },
            observedAt: Dictionary(uniqueKeysWithValues: devices.map { ($0.0, 990) }))
    }

    @Test func devicesTurnTheAccessoryFlagOnAndOffInPairs() {
        let watch = Watch<PeripheralBatterySample>()
        let monitor = Monitor()
        let source = devicesSource(watch, monitor)
        #expect(monitor.calls.isEmpty)
        source.start(); source.start()
        #expect(monitor.calls == [true])
        #expect(watch.active == 1)
        watch.deliver?(sample([("1", "AirPods", 80), ("2", "Souris", 15)]))
        #expect(source.reading?.primary == "Souris 15 %")
        #expect(source.reading?.secondary == "+1 autre")
        source.stop(); source.stop()
        #expect(monitor.calls == [true, false])
        #expect(watch.active == 0)
        #expect(source.reading == nil)
        // A second island opening is a second balanced pair.
        source.start(); source.stop()
        #expect(monitor.calls == [true, false, true, false])
    }

    @Test func devicesLeaveTheFlagAloneWhenTheAccessoriesFeatureOwnsIt() {
        let watch = Watch<PeripheralBatterySample>()
        let monitor = Monitor()
        monitor.ownedElsewhere = true
        let source = devicesSource(watch, monitor)
        source.start()
        source.stop()
        #expect(monitor.calls.isEmpty)
    }

    @Test func devicesDoNotClearAFlagTheFeatureTookOverMeanwhile() {
        let watch = Watch<PeripheralBatterySample>()
        let monitor = Monitor()
        let source = devicesSource(watch, monitor)
        source.start()
        monitor.ownedElsewhere = true   // the feature was switched on while the island was open
        source.stop()
        #expect(monitor.calls == [true])
    }

    @Test func devicesGiveNoChipWithoutAReadableLevel() {
        let watch = Watch<PeripheralBatterySample>()
        let source = devicesSource(watch, Monitor())
        source.start()
        watch.deliver?(sample([]))
        #expect(source.reading == nil)
        source.stop()
    }

    // MARK: Timer

    private final class Clock : @unchecked Sendable {
        var reading: TimerReading?
        var toggles = 0
        let sleeps = Counter()
    }

    private func running(_ seconds: TimeInterval) -> TimerReading {
        TimerReading(mode: .timer, phase: .timer, seconds: seconds, duration: 300, isRunning: true, isPaused: false)
    }

    private func timerSource(_ clock: Clock, _ watch: Watch<Void>) -> TimerChipSource {
        TimerChipSource(hooks: .init(
            changes: { deliver in watch.make { _ in deliver() } },
            current: { clock.reading },
            toggle: { clock.toggles += 1 },
            sleep: { _ in clock.sleeps.bump(); try await Task.sleep(for: .seconds(3600)) }))
    }

    @Test func timerFollowsTheSessionAndTicksOnlyWhileItRuns() async throws {
        let clock = Clock()
        let watch = Watch<Void>()
        let source = timerSource(clock, watch)
        source.start()
        #expect(source.reading == nil)       // no session: no chip, no tick
        await pause()
        #expect(clock.sleeps.value == 0)
        clock.reading = running(272)
        watch.deliver?(())
        #expect(source.reading?.primary == "4:32")
        await until { clock.sleeps.value == 1 }
        #expect(clock.sleeps.value == 1)     // the one-second tick of a running clock
        let toggle = try #require(source.reading?.actions.first)
        toggle.handler()
        #expect(clock.toggles == 1)
        clock.reading = TimerReading(mode: .timer, phase: .timer, seconds: 272, duration: 300, isRunning: false, isPaused: true)
        watch.deliver?(())
        #expect(source.reading?.actions.map(\.title) == ["Reprendre"])
        await pause()
        #expect(clock.sleeps.value == 1)     // paused: the tick is gone and no new one starts
        source.stop()
        #expect(source.reading == nil)
        #expect(watch.active == 0)
    }

    @Test func timerStartAndStopAreIdempotentAndQuietAfterStop() async {
        let clock = Clock()
        clock.reading = running(100)
        let watch = Watch<Void>()
        let source = timerSource(clock, watch)
        source.start(); source.start()
        #expect(watch.subscribed == 1)
        #expect(source.reading != nil)
        source.stop(); source.stop()
        #expect(watch.active == 0)
        await pause()
        let sleeps = clock.sleeps.value
        await pause()
        #expect(clock.sleeps.value == sleeps)
        #expect(source.reading == nil)
    }

    // MARK: Temperature lease: start/stop balance on SystemMonitor's panel counter

    private final class Panel : @unchecked Sendable {
        var appeared = 0
        var disappeared = 0
        var temperature: Double? = 61
        var balance: Int { appeared - disappeared }
    }

    private func lease(_ panel: Panel, idle: Duration = .seconds(8), sleep: @escaping @Sendable (Duration) async throws -> Void = StatusChipsBridgeLifecycleTests.parked) -> CPUTemperatureLease {
        CPUTemperatureLease(hooks: .init(acquire: { panel.appeared += 1 }, release: { panel.disappeared += 1 },
                                         read: { panel.temperature }, sleep: sleep), idleTimeout: idle)
    }

    @Test func leaseTakesOneReferenceHoweverManyTimesItIsCalled() {
        let panel = Panel()
        let lease = lease(panel)
        #expect(panel.appeared == 0)   // nothing until the Load chip asks
        for _ in 0..<10 { #expect(lease.temperature() == 61) }
        #expect(panel.appeared == 1)
        #expect(panel.disappeared == 0)
        lease.expire()
        #expect(panel.balance == 0)
        lease.expire()
        #expect(panel.disappeared == 1)   // idempotent
    }

    @Test func leaseReacquiresAfterARelease() {
        let panel = Panel()
        let lease = lease(panel)
        _ = lease.temperature(); lease.expire()
        _ = lease.temperature(); lease.expire()
        #expect(panel.appeared == 2)
        #expect(panel.disappeared == 2)
    }

    @Test func leaseGivesTheReferenceBackWhenTheLoadChipStopsCalling() async {
        let panel = Panel()
        let lease = lease(panel, idle: .milliseconds(1), sleep: { _ in })   // the idle wait elapses at once
        _ = lease.temperature()
        #expect(panel.balance == 1)
        await until { panel.balance == 0 }
        #expect(panel.balance == 0)
        #expect(lease.isHeld == false)
    }

    @Test func leaseStaysHeldWhileCallsKeepComing() async {
        let panel = Panel()
        let lease = lease(panel)   // the idle wait never elapses on its own
        _ = lease.temperature()
        await settle()
        _ = lease.temperature()
        await settle()
        #expect(panel.balance == 1)
        lease.expire()
        #expect(panel.balance == 0)
    }

    @Test func staleOrBrokenTemperaturesAreNotShown() {
        typealias Hooks = CPUTemperatureLease.Hooks
        #expect(Hooks.fresh(61, readAt: 990, now: 1000) == 61)
        #expect(Hooks.fresh(61, readAt: 900, now: 1000) == nil)   // carried over from an earlier run
        #expect(Hooks.fresh(61, readAt: nil, now: 1000) == nil)
        #expect(Hooks.fresh(nil, readAt: 990, now: 1000) == nil)
        #expect(Hooks.fresh(.nan, readAt: 990, now: 1000) == nil)
    }
}
