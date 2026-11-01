import Foundation
import IslandKit

/// Processor load and memory in use, every 2 seconds, off the main thread, only while the pill shows them.
/// The load is rounded to 5 % and the memory to 0,1 Go; a tick whose shown strings did not change posts nothing,
/// so the main actor hears from this sampler only when the pill would actually redraw.
@MainActor
public final class SystemSampler: AmbientSampler {
    public let channel = AmbientChannel.system
    public nonisolated static let interval: Duration = .seconds(2)

    private struct Memory {
        var ticks: CPUTicks?
        var shownCPU: Int?
        var shownMemory: String?
    }

    private let poller: AmbientPoller
    private let state: SamplerState<Memory>

    /// `readTicks` / `readMemory` / `readPressure` are injectable so a test drives the math with fake counters.
    public convenience init(center: AmbientCenter) {
        self.init(center: center, readTicks: { SystemCounters.cpuTicks() }, readMemory: { SystemCounters.usedMemory() },
                  readPressure: { SystemCounters.memoryPressure() })
    }

    init(center: AmbientCenter, interval: Duration = SystemSampler.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         readTicks: @escaping @Sendable () -> CPUTicks?, readMemory: @escaping @Sendable () -> UInt64?,
         readPressure: @escaping @Sendable () -> MemoryPressure) {
        let state = SamplerState(Memory())
        self.state = state
        poller = AmbientPoller(interval: interval, sleep: sleep) { [weak center] in
            var posts: [AmbientIndicator] = []
            state.withValue { memory in
                if let now = readTicks() {
                    if let before = memory.ticks, let load = SamplingMath.cpuLoad(previous: before, current: now) {
                        let shown = AmbientFormat.roundedPercent(load)
                        if shown != memory.shownCPU {
                            memory.shownCPU = shown
                            posts.append(AmbientReadings.cpu(load: load))
                        }
                    }
                    memory.ticks = now
                }
                if let used = readMemory() {
                    let pressure = readPressure()
                    let key = "\(AmbientFormat.gigabytes(used))|\(pressure.rawValue)"
                    if key != memory.shownMemory {
                        memory.shownMemory = key
                        posts.append(AmbientReadings.memory(usedBytes: used, pressure: pressure))
                    }
                }
            }
            guard !posts.isEmpty else { return }
            Task { @MainActor in
                for indicator in posts { center?.post(indicator) }
            }
        }
    }

    public var isRunning: Bool { poller.isRunning }

    public func start(settings: ClosedIslandSettings) { poller.start() }
    public func stop() {
        poller.stop()
        // The next run measures from its own first reading, not from ticks taken before the pill was hidden.
        state.withValue { $0.ticks = nil }
    }
}
