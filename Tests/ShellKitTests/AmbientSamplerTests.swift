import Foundation
import IslandKit
import IslandTestSupport
import IslandUI
import Testing
@testable import ShellKit

/// Sleep driven by hand: every call waits until `fire()`. Counting the calls is counting the timers.
private final class HandSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var count = 0
    private var asked: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock(); waiters.append(c); count += 1; asked.append(duration); lock.unlock()
        }
    }

    var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
    var durations: [Duration] { lock.lock(); defer { lock.unlock() }; return asked }

    func fire() {
        lock.lock(); let all = waiters; waiters = []; lock.unlock()
        all.forEach { $0.resume() }
    }
}

/// A counter several threads may bump.
private final class TickCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    @discardableResult func bump() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// Values handed out one per call, the last one repeating.
private final class ValueScript<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value]
    private var index = 0
    let calls = TickCounter()

    init(_ values: [Value]) { self.values = values }

    func next() -> Value {
        calls.bump()
        lock.lock(); defer { lock.unlock() }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

@MainActor
private final class LevelBox {
    var percent: Int
    init(_ percent: Int) { self.percent = percent }
}

@MainActor
private final class CountingSampler: AmbientSampler {
    let channel: String
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var settingsSeen: [ClosedIslandSettings] = []

    init(_ channel: String) { self.channel = channel }
    func start(settings: ClosedIslandSettings) { starts += 1 }
    func stop() { stops += 1 }
    func settingsChanged(_ settings: ClosedIslandSettings) { settingsSeen.append(settings) }
}

@MainActor
private struct SamplerRig {
    let center: AmbientCenter
    let preferences: ClosedIslandPreferences
    let defaults: UserDefaults
    private let suite: String

    init(isNotched: Bool = false) {
        suite = "ambient-sampler-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        // Not about the migration of `notchIdleContent`, and a suite reads the process-wide registration domain.
        defaults.set(true, forKey: ClosedIslandKeys.migrated)
        preferences = ClosedIslandPreferences(defaults: defaults)
        center = AmbientCenter(activity: ActivityCenter(), preferences: preferences, isNotched: isNotched,
                               sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
private func waitUntil(_ what: String = "", timeout: Double = 10, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// The real system calls, once each: they answer, and one tick costs next to nothing (the numbers are printed).
@Suite struct AmbientSamplerCostTests {
    private func averageMicroseconds(_ runs: Int = 300, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        let elapsed = clock.measure { for _ in 0..<runs { body() } }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return seconds / Double(runs) * 1e6
    }

    @Test func theRealCountersAnswerWithPlausibleValues() throws {
        let ticks = try #require(SystemCounters.cpuTicks())
        #expect(ticks.total > 0 && ticks.busy <= ticks.total)
        let used = try #require(SystemCounters.usedMemory())
        #expect(used > 500_000_000 && used < 4_000_000_000_000)
        let interfaces = SystemCounters.interfaces()
        #expect(interfaces.contains { $0.name == "lo0" })
        let disk = try #require(SystemCounters.diskFreeBytes())
        #expect(disk > 0)
        #expect([MemoryPressure.normal, .warning, .critical].contains(SystemCounters.memoryPressure()))
    }

    @Test func oneTickOfEverySamplerCostsMicroseconds() {
        let cpu = averageMicroseconds { _ = SystemCounters.cpuTicks() }
        let memory = averageMicroseconds { _ = SystemCounters.usedMemory(); _ = SystemCounters.memoryPressure() }
        let network = averageMicroseconds { _ = SamplingMath.counters(from: SystemCounters.interfaces()) }
        let disk = averageMicroseconds(50) { _ = SystemCounters.diskFreeBytes() }
        let format = averageMicroseconds { _ = AmbientFormat.rate(1_234_567); _ = AmbientFormat.percent(0.37) }
        print(String(format: "SAMPLER COST (average per call): cpu %.0f us, memory+pressure %.0f us, network %.0f us, disk %.0f us, format %.1f us",
                     cpu, memory, network, disk, format))
        // Generous: a loaded machine must pass (the disk read is about 6 ms). At the 2 s rate even 50 ms is 2,5 % of one core.
        for (name, value) in [("cpu", cpu), ("memory", memory), ("network", network), ("disk", disk)] {
            #expect(value < 50_000, "\(name) tick took \(value) us")
        }
    }
}

@MainActor
@Suite struct AmbientSamplerTests {
    // MARK: The hub: nothing runs unless the channel is on, the strip is shown and the screens are awake

    @Test func aDisabledChannelsSamplerIsNeverStarted() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let clock = CountingSampler(AmbientChannel.clock), disk = CountingSampler(AmbientChannel.disk)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [clock, disk])
        hub.start()
        #expect(clock.starts == 1)
        #expect(disk.starts == 0 && disk.stops == 0)  // off by default: not even touched
        #expect(hub.runningChannels == [AmbientChannel.clock])
    }

    @Test func anOpenIslandStopsEverySamplerAndTheReturnRestartsThem() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let clock = CountingSampler(AmbientChannel.clock), system = CountingSampler(AmbientChannel.system)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [clock, system])
        hub.start()
        rig.center.setVisible(false)  // the island opened: the closed strip left the screen
        #expect(clock.stops == 1 && system.stops == 1)
        #expect(hub.runningChannels.isEmpty)
        rig.center.setVisible(true)
        #expect(clock.starts == 2 && system.starts == 2)
    }

    @Test func switchingAChannelOffStopsItAndOnStartsIt() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let system = CountingSampler(AmbientChannel.system), mic = CountingSampler(AmbientChannel.mic)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [system, mic])
        hub.start()
        #expect(system.starts == 1 && mic.starts == 0)
        rig.preferences.setEnabled(AmbientChannel.system, false)
        #expect(system.stops == 1)
        rig.preferences.setEnabled(AmbientChannel.mic, true)
        #expect(mic.starts == 1)
        rig.preferences.setEnabled(AmbientChannel.mic, true)  // same value again
        #expect(mic.starts == 1)
    }

    @Test func sleepingDisplaysStopEverythingAndWakingRestoresWhatIsDemanded() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let clock = CountingSampler(AmbientChannel.clock)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [clock])
        hub.start()
        hub.setScreensAwake(false)
        #expect(clock.stops == 1 && hub.runningChannels.isEmpty)
        hub.setScreensAwake(false)  // already asleep
        #expect(clock.stops == 1)
        hub.setScreensAwake(true)
        #expect(clock.starts == 2)
        // Waking while the island is open starts nothing.
        rig.center.setVisible(false)
        hub.setScreensAwake(false)
        hub.setScreensAwake(true)
        #expect(clock.starts == 2)
    }

    @Test func aRepeatedDemandDoesNotRestartARunningSampler() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let clock = CountingSampler(AmbientChannel.clock)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [clock])
        hub.start()
        rig.center.setVisible(true)
        rig.preferences.setRotates(true)
        rig.preferences.reload()
        #expect(clock.starts == 1 && clock.stops == 0)
    }

    @Test func aSettingsChangeReachesOnlyRunningSamplers() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let clock = CountingSampler(AmbientChannel.clock), disk = CountingSampler(AmbientChannel.disk)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [clock, disk])
        hub.start()
        rig.preferences.setClockHours(.h12)
        #expect(clock.settingsSeen.last?.clockHours == .h12)
        #expect(disk.settingsSeen.isEmpty)
    }

    @Test func stoppingTheHubStopsWhatRunsAndIgnoresLaterChanges() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let clock = CountingSampler(AmbientChannel.clock)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [clock])
        hub.start()
        hub.stop()
        #expect(clock.stops == 1)
        rig.center.setVisible(false)
        rig.center.setVisible(true)
        #expect(clock.starts == 1)
    }

    // MARK: Counting clock: a real sampler does no work when it must not

    @Test func aDisabledSystemSamplerNeverReadsATickCounter() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        rig.preferences.setEnabled(AmbientChannel.system, false)
        let sleep = HandSleep(), reads = TickCounter()
        let sampler = SystemSampler(center: rig.center, sleep: { try await sleep.sleep($0) },
                                    readTicks: { reads.bump(); return nil }, readMemory: { reads.bump(); return nil },
                                    readPressure: { .normal })
        let hub = AmbientSamplerHub(center: rig.center, samplers: [sampler])
        hub.start()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(reads.value == 0 && sleep.requests == 0 && !sampler.isRunning)
    }

    @Test func anOpenIslandRunsNoSamplerAtAll() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        rig.center.setVisible(false)
        let sleep = HandSleep(), reads = TickCounter()
        let system = SystemSampler(center: rig.center, sleep: { try await sleep.sleep($0) },
                                   readTicks: { reads.bump(); return nil }, readMemory: { nil }, readPressure: { .normal })
        let disk = DiskSampler(center: rig.center, sleep: { try await sleep.sleep($0) }, read: { reads.bump(); return nil })
        let network = NetworkSampler(center: rig.center, sleep: { try await sleep.sleep($0) }, watchPath: false,
                                     read: { reads.bump(); return [] })
        rig.preferences.setEnabled(AmbientChannel.disk, true)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [system, disk, network])
        hub.start()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(reads.value == 0 && sleep.requests == 0)
        #expect(!system.isRunning && !disk.isRunning && !network.isRunning)
    }

    @Test func aRunningSamplerTicksAtItsRateAndStopsTheMomentTheIslandOpens() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let sleep = HandSleep(), reads = TickCounter()
        let sampler = SystemSampler(center: rig.center, sleep: { try await sleep.sleep($0) },
                                    readTicks: { reads.bump(); return nil }, readMemory: { nil }, readPressure: { .normal })
        let hub = AmbientSamplerHub(center: rig.center, samplers: [sampler])
        hub.start()
        #expect(await waitUntil { reads.value == 1 && sleep.requests == 1 })
        #expect(sleep.durations == [.seconds(2)])  // the lowest useful rate
        sleep.fire()
        #expect(await waitUntil { reads.value == 2 })
        rig.center.setVisible(false)
        #expect(!sampler.isRunning)
        let before = reads.value
        sleep.fire()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(reads.value == before, "the loop ticked after the island opened")
    }

    @Test func theDiskPollsOnceAMinute() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        rig.preferences.setEnabled(AmbientChannel.disk, true)
        let sleep = HandSleep()
        let sampler = DiskSampler(center: rig.center, sleep: { try await sleep.sleep($0) }, read: { 100_000_000_000 })
        let hub = AmbientSamplerHub(center: rig.center, samplers: [sampler])
        hub.start()
        #expect(await waitUntil { sleep.requests == 1 })
        #expect(sleep.durations == [.seconds(60)])
        #expect(await waitUntil { rig.center.content.all.contains { $0.id == "disk" } })
        #expect(rig.center.content.all.first { $0.id == "disk" }?.text == "100 Go")
    }

    // MARK: Posting only when the shown strings change

    @Test func theSystemSamplerPostsOnlyWhenTheRoundedValueChanges() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        rig.preferences.setMaxPerWing(2)
        let ticks = ValueScript([CPUTicks(busy: 0, total: 0), CPUTicks(busy: 100, total: 200), CPUTicks(busy: 202, total: 400),
                            CPUTicks(busy: 212, total: 600), CPUTicks(busy: 392, total: 800)])
        let sleep = HandSleep()
        let sampler = SystemSampler(center: rig.center, sleep: { try await sleep.sleep($0) },
                                    readTicks: { ticks.next() }, readMemory: { 9_200_000_000 }, readPressure: { .warning })
        sampler.start(settings: .standard)
        func text(_ id: String) -> String? { rig.center.content.all.first { $0.id == id }?.text }
        // First tick: only the baseline for the processor, but the memory shows at once.
        #expect(await waitUntil { text("system.mem") == "9,2 Go" })
        #expect(text("system.cpu") == nil)
        #expect(rig.center.content.all.first { $0.id == "system.mem" }?.status == .warning)
        sleep.fire()
        #expect(await waitUntil { text("system.cpu") == "50%" })  // 100 of 200
        sleep.fire()
        #expect(await waitUntil { ticks.calls.value == 3 })
        try? await Task.sleep(for: .milliseconds(60))
        #expect(text("system.cpu") == "50%")  // 102 of 200 is 51 %: the pill does not redraw
        sleep.fire()
        #expect(await waitUntil { text("system.cpu") == "5%" })  // 3 of 200
        sleep.fire()
        #expect(await waitUntil { text("system.cpu") == "90%" })  // 180 of 200
        sampler.stop()
    }

    @Test func aRestartedSystemSamplerMeasuresFromItsOwnFirstReading() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let ticks = ValueScript([CPUTicks(busy: 0, total: 0), CPUTicks(busy: 100, total: 200),
                            CPUTicks(busy: 1_000_000, total: 2_000_000), CPUTicks(busy: 1_000_050, total: 2_000_100)])
        let sleep = HandSleep()
        let sampler = SystemSampler(center: rig.center, sleep: { try await sleep.sleep($0) },
                                    readTicks: { ticks.next() }, readMemory: { nil }, readPressure: { .normal })
        sampler.start(settings: .standard)
        #expect(await waitUntil { sleep.requests == 1 })
        sleep.fire()
        #expect(await waitUntil { rig.center.content.all.contains { $0.id == "system.cpu" } })
        sampler.stop()
        sleep.fire()
        sampler.start(settings: .standard)
        #expect(await waitUntil { ticks.calls.value == 3 })
        sleep.fire()
        #expect(await waitUntil { ticks.calls.value == 4 })
        // 50 busy in 100 ticks of the second run: 50 %, not the average over the hidden hours.
        #expect(await waitUntil { rig.center.content.all.first { $0.id == "system.cpu" }?.text == "50%" })
        sampler.stop()
    }

    @Test func theNetworkSamplerShowsTheLinkThenTheRates() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        func wifi(_ down: UInt64, _ up: UInt64, vpn: Bool = false) -> [InterfaceReading] {
            var out = [InterfaceReading(name: "en0", isUp: true, hasIPv4: true, counters: InterfaceCounters(bytesIn: down, bytesOut: up)),
                       InterfaceReading(name: "lo0", isUp: true, hasIPv4: true, counters: InterfaceCounters(bytesIn: down * 9, bytesOut: up * 9))]
            if vpn { out.append(InterfaceReading(name: "utun4", isUp: true, hasIPv4: true, counters: nil)) }
            return out
        }
        let script = ValueScript([wifi(0, 0), wifi(4_000_000_000, 2_000_000_000, vpn: true)])
        let sleep = HandSleep()
        let sampler = NetworkSampler(center: rig.center, sleep: { try await sleep.sleep($0) }, watchPath: false, read: { script.next() })
        sampler.start(settings: .standard)
        func item(_ id: String) -> AmbientIndicator? { rig.center.content.all.first { $0.id == id } }
        #expect(await waitUntil { sleep.requests == 1 })
        // The first reading has no delta yet and no tunnel: nothing is drawn, never a bare arrow or "0 Ko/s".
        #expect(item("network.0link") == nil && item("network.1down") == nil && item("network.2up") == nil)
        try? await Task.sleep(for: .milliseconds(30))
        sleep.fire()
        #expect(await waitUntil { item("network.0link")?.text == "VPN" })
        // 4 GB over a few milliseconds is far above 100 Mo/s: the unit moves up, the loopback is not counted twice.
        #expect(item("network.1down")?.text?.hasSuffix("Go/s") == true || item("network.1down")?.text?.hasSuffix("Mo/s") == true)
        #expect(item("network.1down")?.text != "0 Ko/s")
        sampler.stop()
    }

    // MARK: The clock: one timer, aligned to the minute

    private let moment = Date(timeIntervalSince1970: 1_793_534_400 + 30)  // 12:00:30 UTC

    private final class Moment: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date
        init(_ date: Date) { self.date = date }
        var value: Date { lock.lock(); defer { lock.unlock() }; return date }
        func set(_ date: Date) { lock.lock(); self.date = date; lock.unlock() }
    }

    @Test func theClockSleepsToTheNextMinuteBoundaryAndPostsTheNewTime() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let now = Moment(moment), sleep = HandSleep()
        let sampler = ClockSampler(center: rig.center, now: { now.value }, sleep: { try await sleep.sleep($0) },
                                   locale: { Locale(identifier: "fr_FR") })
        var settings = ClosedIslandSettings.standard
        settings.clockHours = .h24
        sampler.start(settings: settings)
        let first = rig.center.content.center?.text
        #expect(first != nil)  // posted at once, before any timer fires
        #expect(await waitUntil { sleep.requests == 1 })
        let wait = sleep.durations[0].components.seconds
        #expect(wait == 29 || wait == 30)  // 30 s to the boundary plus a hair
        now.set(moment.addingTimeInterval(31))
        sleep.fire()
        #expect(await waitUntil { sleep.requests == 2 })
        #expect(rig.center.content.center?.text != first)
        sampler.stop()
        #expect(!sampler.isRunning)
    }

    @Test func aStoppedClockHoldsNoTimerAndASettingsChangeRepostsTheText() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let now = Moment(Date(timeIntervalSince1970: 1_793_534_400 + 14 * 3600 + 10))
        let sleep = HandSleep()
        let sampler = ClockSampler(center: rig.center, now: { now.value }, sleep: { try await sleep.sleep($0) },
                                   locale: { Locale(identifier: "fr_FR") })
        #expect(sleep.requests == 0 && !sampler.isRunning)
        var settings = ClosedIslandSettings.standard
        settings.clockHours = .h24
        sampler.start(settings: settings)
        #expect(await waitUntil { sleep.requests == 1 })
        let h24 = rig.center.content.center?.text
        settings.clockHours = .h12
        sampler.settingsChanged(settings)
        #expect(rig.center.content.center?.text != h24)
        #expect(rig.center.content.center?.text?.contains("PM") == true || rig.center.content.center?.text?.contains("AM") == true)
        sampler.stop()
        let requested = sleep.requests
        sleep.fire()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(sleep.requests == requested, "a stopped clock asked for another timer")
    }

    @Test func theClockStopsWithThePillAndRestartsWithItThroughTheHub() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let sleep = HandSleep()
        let sampler = ClockSampler(center: rig.center, sleep: { try await sleep.sleep($0) })
        let hub = AmbientSamplerHub(center: rig.center, samplers: [sampler])
        hub.start()
        #expect(sampler.isRunning)
        rig.center.setVisible(false)
        #expect(!sampler.isRunning)
        rig.center.setVisible(true)
        #expect(sampler.isRunning)
    }

    // MARK: The volume bar

    @Test func theVolumeBarShowsForOneAndAHalfSecondsThenRestores() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        rig.preferences.setEnabled(AmbientChannel.volume, true)
        let level = LevelBox(30)
        let sleep = HandSleep()
        let sampler = VolumeSampler(center: rig.center, sleep: { try await sleep.sleep($0) }, read: { (level.percent, false) })
        sampler.start(settings: .standard)
        sampler.baseline()
        func hud() -> AmbientIndicator? { rig.center.content.all.first { $0.id == "volume" } }
        #expect(hud() == nil)  // the baseline shows nothing
        sampler.changed()  // same value as the baseline: not a change
        #expect(hud() == nil)
        level.percent = 62
        sampler.changed()
        #expect(hud()?.text == "62%" && hud()?.bar == 0.62)
        #expect(await waitUntil { sleep.requests == 1 })
        #expect(sleep.durations == [.milliseconds(1500)])
        sleep.fire()
        #expect(await waitUntil { hud() == nil })
        sampler.stop()
    }

    @Test func aNewVolumeChangeRestartsTheHold() async {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        rig.preferences.setEnabled(AmbientChannel.volume, true)
        let level = LevelBox(10)
        let sleep = HandSleep()
        let sampler = VolumeSampler(center: rig.center, sleep: { try await sleep.sleep($0) }, read: { (level.percent, false) })
        sampler.start(settings: .standard)
        sampler.baseline()
        level.percent = 20
        sampler.changed()
        level.percent = 30
        sampler.changed()
        #expect(rig.center.content.all.first { $0.id == "volume" }?.text == "30%")
        #expect(await waitUntil { sleep.requests == 2 })  // the first hold was cancelled by the second change, a new one began
        sampler.stop()
        #expect(rig.center.content.all.first { $0.id == "volume" } == nil)  // stopping takes the bar away at once
    }

    // MARK: Event listeners attach and detach cleanly

    @Test func micCameraAndVolumeListenersStartAndStopWithoutHardwareAssumptions() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let mic = MicSampler(center: rig.center), camera = CameraSampler(center: rig.center), volume = VolumeSampler(center: rig.center)
        for _ in 0..<2 {
            mic.start(settings: .standard); camera.start(settings: .standard); volume.start(settings: .standard)
            #expect(mic.isListening && camera.isListening && volume.isListening)
            mic.start(settings: .standard)  // idempotent
            mic.stop(); camera.stop(); volume.stop()
            #expect(!mic.isListening && !camera.isListening && !volume.isListening)
        }
    }

    @Test func offByDefaultChannelsAttachNoListener() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let mic = MicSampler(center: rig.center), camera = CameraSampler(center: rig.center), volume = VolumeSampler(center: rig.center)
        let hub = AmbientSamplerHub(center: rig.center, samplers: [mic, camera, volume])
        hub.start()
        #expect(!mic.isListening && !camera.isListening && !volume.isListening)
        rig.preferences.setEnabled(AmbientChannel.mic, true)
        #expect(mic.isListening && !camera.isListening)
        rig.center.setVisible(false)
        #expect(!mic.isListening)
    }

    @Test func theStandardSetCoversEverySamplerChannelOnce() {
        let rig = SamplerRig(); defer { rig.cleanUp() }
        let channels = AmbientSamplers.standard(center: rig.center).map(\.channel)
        #expect(Set(channels).count == channels.count)
        #expect(Set(channels) == [AmbientChannel.clock, AmbientChannel.system, AmbientChannel.network, AmbientChannel.disk,
                                  AmbientChannel.mic, AmbientChannel.camera, AmbientChannel.volume])
    }
}
