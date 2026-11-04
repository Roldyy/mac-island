import Foundation
import IslandKit

/// "Charge": processor and memory percentages, with the temperature when the app supplies one.
///
/// Sampled every 2 seconds off the main thread (the same counters as the closed island's pill), only between
/// `start()` and `stop()`. The processor needs two samples: the first tick of a run takes a short second one
/// (`primeDelay`) so the chip does not wait 2 s to appear. The temperature is read on the main actor each time a
/// reading is built; another lane injects it (`temperatureProvider`).
@MainActor
final class LoadChipSource: StatusChipPolledSource {
    nonisolated static let interval: Duration = .seconds(2)

    /// One tick's numbers. `cpu` and `memory` are fractions 0...1; nil when the system did not answer.
    struct Snapshot: Equatable, Sendable {
        var cpu: Double?
        var memory: Double?
        var pressure: MemoryPressure
    }

    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let readTicks: @Sendable () -> CPUTicks?
    private let readMemory: @Sendable () -> UInt64?
    private let readPressure: @Sendable () -> MemoryPressure
    private let totalMemory: UInt64
    private let primeDelay: UInt32
    private let state = SamplerState<CPUTicks?>(nil)
    /// Bumped by every `end()`: a tick of an older run recognises itself and drops its baseline.
    private let runGeneration = SamplerState<Int>(0)
    private let temperatureProvider: (@MainActor () -> Double?)?
    private let openMonitor: (@MainActor () -> Void)?
    private var poller: AmbientPoller?

    /// `primeDelay` is in microseconds (0 in tests).
    init(interval: Duration = LoadChipSource.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = StatusChipPolledSource.sleeper(tolerance: .milliseconds(500)),
         readTicks: @escaping @Sendable () -> CPUTicks? = { SystemCounters.cpuTicks() },
         readMemory: @escaping @Sendable () -> UInt64? = { SystemCounters.usedMemory() },
         readPressure: @escaping @Sendable () -> MemoryPressure = { SystemCounters.memoryPressure() },
         totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
         primeDelay: UInt32 = 250_000,
         temperatureProvider: (@MainActor () -> Double?)? = nil,
         openMonitor: (@MainActor () -> Void)? = nil) {
        self.interval = interval
        self.sleep = sleep
        self.readTicks = readTicks
        self.readMemory = readMemory
        self.readPressure = readPressure
        self.totalMemory = totalMemory
        self.primeDelay = primeDelay
        self.temperatureProvider = temperatureProvider
        self.openMonitor = openMonitor
        super.init(kind: .load)
    }

    // MARK: - Reading

    /// The chip for one snapshot: "CPU 25 %" then "RAM 61 %" (and " · 62 °C"). Nil with nothing to show.
    static func reading(_ snapshot: Snapshot, temperature: Double?,
                        openMonitor: (@MainActor () -> Void)? = nil) -> StatusChipReading? {
        guard snapshot.cpu != nil || snapshot.memory != nil else { return nil }
        var parts: [String] = []
        let primary: String
        if let cpu = snapshot.cpu {
            primary = "CPU \(StatusChipLevels.percent(cpu))"
            if let memory = snapshot.memory { parts.append("RAM \(StatusChipLevels.percent(memory, step: 1))") }
        } else if let memory = snapshot.memory {
            primary = "RAM \(StatusChipLevels.percent(memory, step: 1))"
        } else {
            return nil
        }
        if let temperature { parts.append(StatusChipLevels.temperature(temperature)) }
        let level = max(snapshot.cpu.map(StatusChipLevels.cpu) ?? .normal, StatusChipLevels.memory(snapshot.pressure))
        var actions: [StatusChipAction] = []
        if let openMonitor {
            actions.append(StatusChipAction(id: "monitor", title: "Ouvrir le Moniteur",
                                            systemImage: "chart.line.uptrend.xyaxis", handler: openMonitor))
        }
        return StatusChipReading(kind: .load, primary: primary, secondary: parts.isEmpty ? nil : parts.joined(separator: " · "),
                                 level: level, actions: actions)
    }

    // MARK: - Sampling

    override func begin() {
        let state = self.state, readTicks = self.readTicks, readMemory = self.readMemory
        let readPressure = self.readPressure, total = Double(max(totalMemory, 1)), primeDelay = self.primeDelay
        let generation = self.runGeneration
        let myRun = generation.withValue { $0 }
        let tick: @Sendable () -> Void = { [weak self] in
            var cpu: Double?
            var previous = state.withValue { $0 }
            var now = readTicks()
            if previous == nil, let first = now {
                // First tick of a run: a short second sample gives the load of the last instants. The wait holds
                // no lock, so `end()` (main actor) never stalls behind it.
                if primeDelay > 0 { usleep(primeDelay) }
                previous = first
                now = readTicks() ?? first
            }
            if let before = previous, let current = now { cpu = SamplingMath.cpuLoad(previous: before, current: current) }
            // A tick that outlived its run (stopped meanwhile) must not leave a baseline for the next one.
            if let current = now, generation.withValue({ $0 }) == myRun { state.withValue { $0 = current } }
            let memory = readMemory().map { min(max(Double($0) / total, 0), 1) }
            let snapshot = Snapshot(cpu: cpu, memory: memory, pressure: readPressure())
            Task { @MainActor in self?.apply(snapshot) }
        }
        poller = AmbientPoller(interval: interval, sleep: sleep, tick: tick)
        poller?.start()
    }

    override func end() {
        poller?.stop()
        poller = nil
        // The next run measures from its own first reading, not from ticks taken before the island closed.
        runGeneration.withValue { $0 += 1 }
        state.withValue { $0 = nil }
    }

    private func apply(_ snapshot: Snapshot) {
        publish(Self.reading(snapshot, temperature: temperatureProvider?(), openMonitor: openMonitor))
    }
}
