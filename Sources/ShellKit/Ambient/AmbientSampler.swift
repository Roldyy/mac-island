import Foundation
import IslandKit

/// A source of closed-island indicators that costs something while it runs (a timer, a listener). The hub
/// starts it only while its channel is switched on and the closed strip is on screen, and stops it otherwise,
/// so a disabled indicator or an open island does no work at all.
@MainActor
public protocol AmbientSampler: AnyObject {
    /// The `AmbientChannel` this sampler feeds. One sampler, one channel.
    var channel: String { get }
    /// Idempotent. Takes a reading at once, then keeps the indicator current.
    func start(settings: ClosedIslandSettings)
    /// Idempotent. Cancels every timer and removes every listener.
    func stop()
    /// A running sampler hears about a Settings change (the clock's hour cycle).
    func settingsChanged(_ settings: ClosedIslandSettings)
}

public extension AmbientSampler {
    func settingsChanged(_ settings: ClosedIslandSettings) {}
}

/// A low-rate loop that runs off the main thread: `tick` is called now, then once per `interval`. The tick does
/// its own reading and decides whether anything changed; only then does it hop to the main actor.
///
/// `sleep` is injectable so a test counts the ticks without waiting.
public final class AmbientPoller: @unchecked Sendable {
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let tick: @Sendable () -> Void
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(interval: Duration,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                tick: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.sleep = sleep
        self.tick = tick
    }

    deinit { task?.cancel() }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return task != nil
    }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard task == nil else { return }
        let interval = self.interval, sleep = self.sleep, tick = self.tick
        task = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                tick()
                do { try await sleep(interval) } catch { return }
            }
        }
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        task?.cancel()
        task = nil
    }
}

/// Mutable state a poller's tick keeps between two calls. The tick is the only user, one call at a time.
final class SamplerState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
