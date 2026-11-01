import Foundation
import IslandKit

/// Free space on the startup volume, once a minute. A volume does not fill up faster than that.
@MainActor
public final class DiskSampler: AmbientSampler {
    public let channel = AmbientChannel.disk
    public nonisolated static let interval: Duration = .seconds(60)

    private let poller: AmbientPoller

    public convenience init(center: AmbientCenter) {
        self.init(center: center, read: { SystemCounters.diskFreeBytes() })
    }

    init(center: AmbientCenter, interval: Duration = DiskSampler.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         read: @escaping @Sendable () -> UInt64?) {
        let shown = SamplerState<String?>(nil)
        poller = AmbientPoller(interval: interval, sleep: sleep) { [weak center] in
            guard let free = read() else { return }
            let text = AmbientFormat.gigabytes(free)
            guard shown.withValue({ last in
                defer { last = text }
                return last != text
            }) else { return }
            let indicator = AmbientReadings.disk(freeBytes: free)
            Task { @MainActor in center?.post(indicator) }
        }
    }

    public var isRunning: Bool { poller.isRunning }

    public func start(settings: ClosedIslandSettings) { poller.start() }
    public func stop() { poller.stop() }
}
