import Foundation
import IslandKit
import Network

/// Live throughput, the connection glyph and a VPN tag. Byte counters are read every 2 seconds off the main
/// thread (a delta of `getifaddrs`, physical interfaces only); the connection type comes from `NWPathMonitor`,
/// which calls back only when the path changes. Rates are shown with 3 significant digits and the main actor
/// hears from this sampler only when one of the shown strings changed.
@MainActor
public final class NetworkSampler: AmbientSampler {
    public let channel = AmbientChannel.network
    public nonisolated static let interval: Duration = .seconds(2)

    private struct Memory {
        var counters: [String: InterfaceCounters]?
        var at: ContinuousClock.Instant?
        var link: NetworkLink = .other
        var shown: String?
    }

    private weak var center: AmbientCenter?
    private let state: SamplerState<Memory>
    private let poller: AmbientPoller
    private let read: @Sendable () -> [InterfaceReading]
    private let watchPath: Bool
    private var started = false
    private let pathQueue = DispatchQueue(label: "be.roldy.macisland.network-path", qos: .utility)
    private var monitor: NWPathMonitor?
    private let tick: @Sendable () -> Void

    public convenience init(center: AmbientCenter) {
        self.init(center: center, read: { SystemCounters.interfaces() })
    }

    /// `watchPath: false` keeps the connection type at "other": a test then sees only its own fake readings.
    init(center: AmbientCenter, interval: Duration = NetworkSampler.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         watchPath: Bool = true, read: @escaping @Sendable () -> [InterfaceReading]) {
        self.center = center
        self.read = read
        self.watchPath = watchPath
        let state = SamplerState(Memory())
        self.state = state
        let tick: @Sendable () -> Void = { [weak center] in
            let readings = read()
            let counters = SamplingMath.counters(from: readings)
            let vpn = SamplingMath.vpnActive(readings)
            let now = ContinuousClock.now
            let posts: [AmbientIndicator]? = state.withValue { memory in
                defer { memory.counters = counters; memory.at = now }
                var down = 0.0, up = 0.0
                if let before = memory.counters, let at = memory.at {
                    let elapsed = at.duration(to: now)
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    (down, up) = SamplingMath.throughput(SamplingMath.delta(previous: before, current: counters), seconds: seconds)
                } else if memory.shown != nil {
                    // First reading after a pause: no rate yet, keep what the pill already shows.
                    return nil
                }
                let signature = AmbientReadings.networkSignature(link: memory.link, vpn: vpn, down: down, up: up)
                guard signature != memory.shown else { return nil }
                memory.shown = signature
                return AmbientReadings.network(link: memory.link, vpn: vpn, downBytesPerSecond: down, upBytesPerSecond: up)
            }
            guard let posts else { return }
            Task { @MainActor in NetworkSampler.apply(posts, to: center) }
        }
        self.tick = tick
        poller = AmbientPoller(interval: interval, sleep: sleep, tick: tick)
    }

    public var isRunning: Bool { poller.isRunning }

    public func start(settings: ClosedIslandSettings) {
        guard !started else { return }
        started = true
        poller.start()
        guard watchPath else { return }
        // Event driven: one callback per change of path (Wi-Fi to Ethernet, offline, back online).
        let monitor = NWPathMonitor()
        let state = self.state, tick = self.tick
        monitor.pathUpdateHandler = { path in
            let link: NetworkLink
            if path.status != .satisfied { link = .offline } else if path.usesInterfaceType(.wifi) { link = .wifi } else if path.usesInterfaceType(.wiredEthernet) {
                link = .wired
            } else { link = .other }
            let changed = state.withValue { memory in
                defer { memory.link = link }
                return memory.link != link
            }
            if changed { tick() }
        }
        monitor.start(queue: pathQueue)
        self.monitor = monitor
    }

    public func stop() {
        started = false
        poller.stop()
        monitor?.cancel()
        monitor = nil
        // The next run measures from its own first reading.
        state.withValue { $0.counters = nil; $0.at = nil }
    }

    /// Posts what is shown and withdraws what is not (the rates while offline).
    static func apply(_ indicators: [AmbientIndicator], to center: AmbientCenter?) {
        guard let center else { return }
        let ids = Set(indicators.map(\.id))
        for indicator in indicators { center.post(indicator) }
        for id in AmbientReadings.networkIDs where !ids.contains(id) { center.withdraw(id: id) }
    }
}
