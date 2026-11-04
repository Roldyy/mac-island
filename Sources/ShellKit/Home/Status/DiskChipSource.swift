import Foundation
import IslandKit

/// "Disque": free space on the startup volume. Read once a minute, off the main thread, only between `start()` and
/// `stop()` (a volume does not fill up faster than that).
@MainActor
final class DiskChipSource: StatusChipPolledSource {
    nonisolated static let interval: Duration = .seconds(60)

    /// Free and total bytes of the volume.
    struct Volume: Equatable, Sendable {
        var free: UInt64
        var total: UInt64
    }

    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let read: @Sendable () -> Volume?
    private let openMonitor: (@MainActor () -> Void)?
    private var poller: AmbientPoller?

    init(interval: Duration = DiskChipSource.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = StatusChipPolledSource.sleeper(tolerance: .seconds(10)),
         read: @escaping @Sendable () -> Volume? = { DiskChipSource.startupVolume() },
         openMonitor: (@MainActor () -> Void)? = nil) {
        self.interval = interval
        self.sleep = sleep
        self.read = read
        self.openMonitor = openMonitor
        super.init(kind: .disk)
    }

    /// Free space as Finder counts it (`SystemCounters.diskFreeBytes`) over the volume's capacity.
    nonisolated static func startupVolume() -> Volume? {
        guard let free = SystemCounters.diskFreeBytes() else { return nil }
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
        guard let total = values?.volumeTotalCapacity, total > 0 else { return nil }
        return Volume(free: free, total: UInt64(total))
    }

    /// "412 Go libres", attention under 10 % free, alert under 5 %.
    static func reading(_ volume: Volume, openMonitor: (@MainActor () -> Void)? = nil) -> StatusChipReading {
        let fraction = volume.total > 0 ? Double(volume.free) / Double(volume.total) : 1
        var actions: [StatusChipAction] = []
        if let openMonitor {
            actions.append(StatusChipAction(id: "monitor", title: "Ouvrir le Moniteur",
                                            systemImage: "chart.line.uptrend.xyaxis", handler: openMonitor))
        }
        return StatusChipReading(kind: .disk, primary: AmbientFormat.gigabytes(volume.free), secondary: "libres",
                                 level: StatusChipLevels.disk(freeFraction: fraction), actions: actions)
    }

    override func begin() {
        let read = self.read
        let tick: @Sendable () -> Void = { [weak self] in
            guard let volume = read() else { return }
            Task { @MainActor in self?.apply(volume) }
        }
        poller = AmbientPoller(interval: interval, sleep: sleep, tick: tick)
        poller?.start()
    }

    override func end() {
        poller?.stop()
        poller = nil
    }

    private func apply(_ volume: Volume) {
        publish(Self.reading(volume, openMonitor: openMonitor))
    }
}
