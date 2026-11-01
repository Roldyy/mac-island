import Foundation
import Testing
@testable import MonitorFeature

@MainActor
@Suite struct MonitorModelTests {
    struct Rig {
        let defaults = TempDefaults()
        let cpu: FakeCPU
        let memory = FakeMemory(usedPercent: 40)
        let thermal = FakeThermal()
        let processes = FakeProcesses()
        let notifier = FakeNotifier()
        let clock = Clock()
        let model: MonitorModel

        @MainActor init(cpuScript: [[CPUTicks]?]) {
            cpu = FakeCPU(cpuScript)
            let settings = MonitorSettings(defaults: defaults.defaults)
            let c = clock
            model = MonitorModel(settings: settings, cpu: cpu, memory: memory, thermal: thermal,
                                 processes: processes, notifier: notifier,
                                 clock: { c.now }, uptimeNs: { c.uptimeNs })
        }
        @MainActor func tick(after seconds: TimeInterval = 1) {
            clock.advance(seconds)
            model.tick()
        }
    }

    /// CPU ticks that read as `pct` busy between two consecutive ticks of 100 ticks per core.
    private func script(percentages: [Int]) -> [[CPUTicks]?] {
        var user: UInt32 = 0, idle: UInt32 = 0
        var out: [[CPUTicks]?] = [busy(2, user: 0, idle: 0)]
        for p in percentages {
            user += UInt32(p); idle += UInt32(100 - p)
            out.append(busy(2, user: user, idle: idle))
        }
        return out
    }

    @Test func firstTickOnlySetsTheCPUBaseline() {
        let r = Rig(cpuScript: script(percentages: [50]))
        r.model.tick()
        #expect(r.model.cpuPercent == nil)
        #expect(r.model.memoryPercent == 40)
        r.tick()
        #expect(r.model.cpuPercent == 50)
        #expect(r.model.cpuHistory.values == [50])
    }

    @Test func memoryPressureAndThermalAreReported() {
        let r = Rig(cpuScript: script(percentages: [10]))
        r.memory.level = .warning
        r.thermal.current = .serious
        r.model.tick()
        #expect(r.model.pressure == .warning)
        #expect(r.model.thermal == .serious)
    }

    @Test func processesAreSampledOnlyWhileVisible() {
        let r = Rig(cpuScript: script(percentages: [10, 10, 10]))
        r.processes.raws = [ProcessRaw(pid: 4, cpuTimeNs: 0, residentBytes: 500)]
        r.model.tick()
        #expect(r.processes.snapshots == 0)
        r.model.setVisible(true)
        r.tick()
        #expect(r.processes.snapshots == 1)
        #expect(r.model.topByMemory.first?.name == "proc-4")
        #expect(r.model.topByMemory.first?.pid == 4)
        r.model.setVisible(false)
        r.tick()
        #expect(r.processes.snapshots == 1)
        #expect(r.model.topByMemory.isEmpty)
    }

    @Test func topByCPUAppearsOnTheSecondVisibleSample() {
        let r = Rig(cpuScript: script(percentages: [10, 10, 10]))
        r.model.setVisible(true)
        r.processes.raws = [ProcessRaw(pid: 4, cpuTimeNs: 0, residentBytes: 500)]
        r.tick()
        #expect(r.model.topByCPU.isEmpty)
        r.processes.raws = [ProcessRaw(pid: 4, cpuTimeNs: 500_000_000, residentBytes: 500)]
        r.tick()
        #expect(r.model.topByCPU.first?.cpuPercent == 50)
    }

    @Test func cadenceFollowsVisibilityAndAlerts() {
        let r = Rig(cpuScript: script(percentages: [10]))
        r.model.start()
        #expect(r.model.activeInterval == nil)  // hidden + alerts off: nothing runs
        r.model.alertsEnabled = true
        #expect(r.model.activeInterval == 5)
        r.model.setVisible(true)
        #expect(r.model.activeInterval == 1)
        r.model.setVisible(false)
        #expect(r.model.activeInterval == 5)
        r.model.alertsEnabled = false
        #expect(r.model.activeInterval == nil)
        r.model.stop()
    }

    @Test func startAndStopAreIdempotent() {
        let r = Rig(cpuScript: script(percentages: [10]))
        r.model.setVisible(true)
        r.model.start()
        r.model.start()
        #expect(r.model.loopGeneration == 1)
        r.model.stop()
        r.model.stop()
        #expect(r.model.activeInterval == nil)
        r.model.start()
        #expect(r.model.loopGeneration == 2)
        r.model.stop()
    }

    @Test func stopHaltsEvenWhenVisibleAndAlertsOn() {
        let r = Rig(cpuScript: script(percentages: [10]))
        r.model.alertsEnabled = true
        r.model.setVisible(true)
        r.model.start()
        r.model.stop()
        #expect(r.model.activeInterval == nil)
    }

    @Test func settingsChangesArePersisted() {
        let r = Rig(cpuScript: script(percentages: [10]))
        r.model.cpuThreshold = 70
        r.model.sustainedSeconds = 90
        r.model.alertsEnabled = true
        let reread = MonitorSettings(defaults: r.defaults.defaults)
        #expect(reread.cpuThreshold == 70)
        #expect(reread.sustainedSeconds == 90)
        #expect(reread.alertsEnabled)
    }

    @Test func sustainedHighCPURaisesAnInIslandNoticeThenClears() {
        let r = Rig(cpuScript: script(percentages: [95, 95, 95, 95, 95, 20, 20]))
        r.model.alertsEnabled = true
        r.model.sustainedSeconds = 3
        r.model.systemNotificationsEnabled = false
        r.model.tick()                       // baseline
        r.tick(); r.tick()                   // 95 at t+1, t+2: pending
        #expect(r.model.currentAlert == nil)
        r.tick()                             // t+3: sustained for 2 s? pending since t+1 -> 2 s
        r.tick()                             // t+4: 3 s -> raised
        #expect(r.model.currentAlert?.metric == .cpu)
        #expect(r.model.currentAlert?.value == 95)
        r.tick()                             // 95 still: no change
        r.tick()                             // 20: cleared
        #expect(r.model.currentAlert == nil)
        #expect(r.notifier.posted.isEmpty)
    }

    @Test func noEvaluationWhenAlertsAreDisabled() {
        let r = Rig(cpuScript: script(percentages: Array(repeating: 99, count: 10)))
        r.model.sustainedSeconds = 1
        r.model.tick()
        for _ in 0..<9 { r.tick() }
        #expect(r.model.currentAlert == nil)
        #expect(r.model.cpuPercent == 99)
    }

    @Test func memoryAlertUsesItsOwnThreshold() {
        let r = Rig(cpuScript: script(percentages: Array(repeating: 5, count: 10)))
        r.memory.counts = FakeMemory.make(92)
        r.model.alertsEnabled = true
        r.model.memoryThreshold = 90
        r.model.sustainedSeconds = 2
        r.model.tick()
        r.tick(); r.tick()
        #expect(r.model.currentAlert?.metric == .memory)
    }

    /// start() refreshes the (read-only) status itself: a relaunch must not drop notifications the user enabled.
    @Test func systemNotificationPostedOnlyWhenBundledAuthorizedAndEnabled() async {
        let r = Rig(cpuScript: script(percentages: Array(repeating: 95, count: 10)))
        r.model.alertsEnabled = true
        r.model.sustainedSeconds = 2
        r.model.systemNotificationsEnabled = true
        r.model.start()
        for _ in 0..<6000 where r.model.notificationStatus != .authorized { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(r.model.notificationStatus == .authorized)
        #expect(r.notifier.requests == 0)
        r.model.tick()
        r.tick(); r.tick(); r.tick()
        r.model.stop()
        #expect(r.notifier.posted.count == 1)
        #expect(r.model.currentAlert != nil)  // the in-island notice is always shown too
    }

    @Test func noSystemNotificationWithoutBundle() async {
        let r = Rig(cpuScript: script(percentages: Array(repeating: 95, count: 10)))
        r.notifier.hasBundle = false
        r.model.alertsEnabled = true
        r.model.sustainedSeconds = 2
        r.model.systemNotificationsEnabled = true
        await r.model.refreshNotificationStatus()
        r.model.tick()
        r.tick(); r.tick(); r.tick()
        #expect(r.notifier.posted.isEmpty)
        #expect(r.model.currentAlert != nil)
        #expect(r.model.notificationMode == .inIslandOnly)
    }

    @Test func authorizationIsRequestedOnlyByTheExplicitCall() async {
        let r = Rig(cpuScript: script(percentages: [10]))
        r.notifier.status = .notDetermined
        r.model.start()
        await r.model.refreshNotificationStatus()
        r.model.tick()
        #expect(r.notifier.requests == 0)
        await r.model.requestNotificationAuthorization()
        #expect(r.notifier.requests == 1)
        #expect(r.model.notificationStatus == .authorized)
        #expect(r.model.systemNotificationsEnabled)
        r.model.stop()
    }

    @Test func requestIsRefusedWithoutABundle() async {
        let r = Rig(cpuScript: script(percentages: [10]))
        r.notifier.hasBundle = false
        await r.model.requestNotificationAuthorization()
        #expect(r.notifier.requests == 0)
    }

    @Test func dismissingTheNoticeDoesNotReRaiseWhileStillHigh() {
        let r = Rig(cpuScript: script(percentages: Array(repeating: 95, count: 12)))
        r.model.alertsEnabled = true
        r.model.sustainedSeconds = 2
        r.model.tick()
        r.tick(); r.tick(); r.tick()
        #expect(r.model.currentAlert != nil)
        r.model.dismissCurrentAlert()
        #expect(r.model.currentAlert == nil)
        for _ in 0..<5 { r.tick() }
        #expect(r.model.currentAlert == nil)
    }

    @Test func disablingAlertsClearsTheNoticeAndResetsTheEvaluator() {
        let r = Rig(cpuScript: script(percentages: Array(repeating: 95, count: 12)))
        r.model.alertsEnabled = true
        r.model.sustainedSeconds = 2
        r.model.tick()
        r.tick(); r.tick(); r.tick()
        #expect(r.model.currentAlert != nil)
        r.model.alertsEnabled = false
        #expect(r.model.currentAlert == nil)
    }

    @Test func unreadableSamplersDoNotCrashOrAlert() {
        let r = Rig(cpuScript: [nil])
        r.memory.counts = nil
        r.model.alertsEnabled = true
        r.model.tick(); r.tick()
        #expect(r.model.cpuPercent == nil)
        #expect(r.model.memoryPercent == nil)
        #expect(r.model.currentAlert == nil)
    }
}

@Suite struct LiveSamplerTests {
    @Test func cpuTicksAreReadableAndMonotonic() throws {
        let sampler = MachCPUSampler()
        let a = try #require(sampler.ticks())
        #expect(a.count >= 1)
        var x = 0.0
        for i in 0..<2_000_000 { x += Double(i).squareRoot() }
        #expect(x > 0)
        let b = try #require(sampler.ticks())
        #expect(b.count == a.count)
        let usage = UsageMath.cpuUsage(previous: a, current: b)
        if let usage { #expect((0...100).contains(usage)) }
    }

    @Test func memoryCountsAreSane() throws {
        let sampler = MachMemorySampler()
        let c = try #require(sampler.read())
        #expect(c.pageSize >= 4096)
        #expect(c.totalBytes >= 1 << 30)
        let p = UsageMath.memoryUsedPercent(c)
        #expect(p > 1 && p <= 100)
        _ = sampler.pressure()  // a value of the enum, never a crash
    }

    @Test func processSnapshotSeesThisProcessAndNamesIt() throws {
        let sampler = MachProcessSampler()
        let snap = sampler.snapshot()
        let me = ProcessInfo.processInfo.processIdentifier
        let mine = try #require(snap.first { $0.pid == me })
        #expect(mine.residentBytes > 0)
        #expect(!sampler.name(pid: me).isEmpty)
        #expect(sampler.name(pid: -5) == "?")
    }

    @Test func processCPUTimeIsInRealNanoseconds() throws {
        // Spin ~0.3 s of CPU on this thread: the own-process delta must be of that order.
        // A missing mach timebase conversion would read about 24x too small on Apple Silicon.
        let sampler = MachProcessSampler()
        let me = ProcessInfo.processInfo.processIdentifier
        let before = try #require(sampler.snapshot().first { $0.pid == me })
        let began = DispatchTime.now().uptimeNanoseconds
        let end = began + 300_000_000
        var x = 0.0
        while DispatchTime.now().uptimeNanoseconds < end { x += 1.0.squareRoot() }
        #expect(x > 0)
        let after = try #require(sampler.snapshot().first { $0.pid == me })
        let wall = DispatchTime.now().uptimeNanoseconds - began
        let delta = after.cpuTimeNs - before.cpuTimeNs
        #expect(delta >= 200_000_000)
        // The delta is the whole process, and other tests run on every other core meanwhile: the ceiling is every
        // core busy for the measured wall time (plus slack), not a fixed 3 s that a loaded machine exceeds.
        let ceiling = UInt64(ProcessInfo.processInfo.activeProcessorCount) * wall * 3 / 2 + 500_000_000
        #expect(UInt64(delta) <= ceiling)
    }

    @Test func thermalLevelMapsEveryState() {
        #expect(ThermalLevel(.nominal) == .nominal)
        #expect(ThermalLevel(.fair) == .fair)
        #expect(ThermalLevel(.serious) == .serious)
        #expect(ThermalLevel(.critical) == .critical)
    }
}
