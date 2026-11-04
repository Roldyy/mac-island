import Foundation
import IslandKit
import Network

/// "Réseau": the connection type ("Wi-Fi", "Ethernet", "Hors ligne") and the live rates. On Wi-Fi the title is the
/// network name when a `WiFiNameProvider` knows it (Location allowed), otherwise "Wi-Fi".
///
/// Counters are read every 2 seconds off the main thread (the same `getifaddrs` delta as the closed island's pill);
/// the connection type comes from `NWPathMonitor`, which calls back only when the path changes. Both run only
/// between `start()` and `stop()`.
@MainActor
final class NetworkChipSource: StatusChipPolledSource {
    nonisolated static let interval: Duration = .seconds(2)

    /// What one tick measured. Rates are nil until two samples exist.
    struct Snapshot: Equatable, Sendable {
        var link: NetworkLink
        var vpn: Bool
        var down: Double?
        var up: Double?
        /// The Wi-Fi name, already sanitised; nil keeps the title "Wi-Fi".
        var name: String?
    }

    private struct Memory {
        var counters: [String: InterfaceCounters]?
        var at: ContinuousClock.Instant?
        var link: NetworkLink = .other
    }

    private let state = SamplerState(Memory())
    private let read: @Sendable () -> [InterfaceReading]
    private let watchPath: Bool
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let openMonitor: (@MainActor () -> Void)?
    private let nameProvider: WiFiNameProvider?
    private var lastSnapshot: Snapshot?
    private var poller: AmbientPoller?
    private var monitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "be.roldy.macisland.chip-network-path", qos: .utility)

    /// `watchPath: false` keeps the connection type at "other": a test then sees only its own fake readings.
    init(interval: Duration = NetworkChipSource.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = StatusChipPolledSource.sleeper(tolerance: .milliseconds(500)),
         watchPath: Bool = true,
         read: @escaping @Sendable () -> [InterfaceReading] = { SystemCounters.interfaces() },
         openMonitor: (@MainActor () -> Void)? = nil,
         nameProvider: WiFiNameProvider? = nil) {
        self.nameProvider = nameProvider
        self.interval = interval
        self.sleep = sleep
        self.watchPath = watchPath
        self.read = read
        self.openMonitor = openMonitor
        super.init(kind: .network)
    }

    // MARK: - Reading

    /// The chip for one snapshot. Offline is an alert; a rate shows only once it is known.
    static func reading(_ snapshot: Snapshot, openMonitor: (@MainActor () -> Void)? = nil) -> StatusChipReading {
        var actions: [StatusChipAction] = []
        if let openMonitor {
            actions.append(StatusChipAction(id: "monitor", title: "Ouvrir le Moniteur",
                                            systemImage: "chart.line.uptrend.xyaxis", handler: openMonitor))
        }
        let title: String, symbol: String
        switch snapshot.link {
        case .wifi: (title, symbol) = (snapshot.name ?? "Wi-Fi", "wifi")
        case .wired: (title, symbol) = ("Ethernet", "cable.connector.horizontal")
        case .other: (title, symbol) = ("Réseau", "network")
        case .offline: (title, symbol) = ("Hors ligne", "wifi.slash")
        }
        var parts: [String] = []
        if snapshot.vpn { parts.append("VPN") }
        if snapshot.link != .offline, let down = snapshot.down, let up = snapshot.up {
            parts.append(StatusChipLevels.rates(down: down, up: up))
        }
        return StatusChipReading(kind: .network, primary: title, secondary: parts.isEmpty ? nil : parts.joined(separator: " · "),
                                 symbol: symbol, level: snapshot.link == .offline ? .alert : .normal, actions: actions)
    }

    // MARK: - Sampling

    override func begin() {
        let state = self.state, read = self.read
        let tick: @Sendable () -> Void = { [weak self] in
            let readings = read()
            let counters = SamplingMath.counters(from: readings)
            let vpn = SamplingMath.vpnActive(readings)
            let now = ContinuousClock.now
            let snapshot: Snapshot = state.withValue { memory in
                defer { memory.counters = counters; memory.at = now }
                var rates: (down: Double, up: Double)?
                if let before = memory.counters, let at = memory.at {
                    let elapsed = at.duration(to: now)
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    rates = SamplingMath.throughput(SamplingMath.delta(previous: before, current: counters), seconds: seconds)
                }
                return Snapshot(link: memory.link, vpn: vpn, down: rates?.down, up: rates?.up)
            }
            Task { @MainActor in self?.apply(snapshot) }
        }
        // The user answered the Location prompt (or changed it in Settings): show the name now.
        nameProvider?.begin { [weak self] in
            guard let self, let last = self.lastSnapshot else { return }
            self.apply(last)
        }
        poller = AmbientPoller(interval: interval, sleep: sleep, tick: tick)
        poller?.start()
        guard watchPath else { return }
        // Event driven: one callback per change of path (Wi-Fi to Ethernet, offline, back online).
        let monitor = NWPathMonitor()
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

    override func end() {
        poller?.stop()
        poller = nil
        monitor?.cancel()
        monitor = nil
        nameProvider?.end()
        lastSnapshot = nil
        // The next run measures from its own first reading.
        state.withValue { $0.counters = nil; $0.at = nil }
    }

    /// Internal (not private) so a test can feed a link without a path monitor.
    func apply(_ snapshot: Snapshot) {
        guard isRunning else { return }
        lastSnapshot = snapshot
        var named = snapshot
        named.name = nameProvider?.name(forWiFi: snapshot.link == .wifi)
        publish(Self.reading(named, openMonitor: openMonitor))
    }
}
