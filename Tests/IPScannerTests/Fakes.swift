import Foundation
@testable import IPScannerFeature

/// Counts how many calls run at once, so a test can assert the concurrency bound.
final class InFlight: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var peak = 0
    private(set) var started = 0

    func enter() {
        lock.lock(); defer { lock.unlock() }
        current += 1
        started += 1
        peak = max(peak, current)
    }

    func leave() { lock.lock(); current -= 1; lock.unlock() }
}

/// Never opens a socket. Answers for `alive`, stays silent for the rest, after `delay` (cancel-aware).
final class FakeNudger: HostNudging, @unchecked Sendable {
    let flight = InFlight()
    let alive: Set<IPv4Address>
    let delay: Duration
    init(alive: Set<IPv4Address> = [], delay: Duration = .milliseconds(2)) {
        self.alive = alive
        self.delay = delay
    }

    func nudge(_ ip: IPv4Address, timeout: Duration) async -> NudgeOutcome {
        flight.enter()
        defer { flight.leave() }
        try? await Task.sleep(for: delay)
        return alive.contains(ip) ? .answered(latencyMs: 1.5) : .silent
    }
}

final class FakeNeighbors: NeighborTableReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let entries: [ArpEntry]
    init(_ entries: [ArpEntry] = []) { self.entries = entries }
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }

    func read() async -> [ArpEntry] {
        lock.withLock { count += 1 }
        return entries
    }
}

final class FakeResolver: NameResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let names: [IPv4Address: String]
    init(_ names: [IPv4Address: String] = [:]) { self.names = names }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }

    func hostName(for ip: IPv4Address) async -> String? {
        lock.withLock { count += 1 }
        return names[ip]
    }
}

struct FakeDiscovery: ServiceDiscovering {
    var result = ServiceDiscovery()
    func discover(within: Duration, limit: Int) async -> ServiceDiscovery { result }
}

final class FakePortProber: PortProbing, @unchecked Sendable {
    let flight = InFlight()
    private let lock = NSLock()
    private var seen: [UInt16] = []
    let open: Set<UInt16>
    let delay: Duration
    init(open: Set<UInt16> = [], delay: Duration = .milliseconds(1)) {
        self.open = open
        self.delay = delay
    }
    var probed: [UInt16] { lock.lock(); defer { lock.unlock() }; return seen }

    func isOpen(host: IPv4Address, port: UInt16, timeout: Duration) async -> Bool {
        flight.enter()
        defer { flight.leave() }
        lock.withLock { seen.append(port) }
        try? await Task.sleep(for: delay)
        return open.contains(port)
    }
}

final class FakeRunner: ArgvRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(path: String, arguments: [String], maxBytes: Int)] = []
    var output: Data?
    init(output: Data?) { self.output = output }

    func run(path: String, arguments: [String], maxBytes: Int, timeout: Duration) async -> Data? {
        lock.withLock { calls.append((path, arguments, maxBytes)) }
        return output
    }
}

struct FakeInterfaces: InterfaceProviding {
    var list: [LocalInterface]
    func interfaces() -> [LocalInterface] { list }
}

final class FakeFetcher: PublicIPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []
    var answer: String
    init(answer: String = "203.0.113.9\n") { self.answer = answer }

    func fetch(from url: URL) async throws -> String {
        lock.withLock { urls.append(url) }
        return answer
    }
}

final class FakeChecker: LocalNetworkChecking, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var targets: [IPv4Address] = []
    var state: LocalNetworkState
    init(state: LocalNetworkState = .granted) { self.state = state }

    func check(target: IPv4Address) async -> LocalNetworkState {
        lock.withLock { targets.append(target) }
        return state
    }
}

final class Clip: @unchecked Sendable {
    var copied: [String] = []
    var saved: [String] = []
    var opened: [URL] = []
}

enum Fixtures {
    static func ip(_ text: String) -> IPv4Address { IPv4Address(text)! }
    static func subnet(_ cidr: String) -> IPv4Subnet { IPv4Subnet(cidr: cidr)! }
    static func mac(_ text: String) -> MACAddress { MACAddress(text)! }

    static func interface(_ address: String = "192.168.1.20", cidr: String = "192.168.1.0/24", gateway: String? = "192.168.1.1") -> LocalInterface {
        LocalInterface(name: "en0", address: ip(address), subnet: subnet(cidr), gateway: gateway.map(ip))
    }

    static func services(nudger: FakeNudger = FakeNudger(), neighbors: FakeNeighbors = FakeNeighbors(),
                         resolver: FakeResolver = FakeResolver(), discovery: FakeDiscovery = FakeDiscovery()) -> ScanServices {
        ScanServices(nudger: nudger, neighbors: neighbors, resolver: resolver, discovery: discovery)
    }

    @MainActor
    static func environment(interfaces: [LocalInterface] = [interface()], services: ScanServices = services(),
                            ports: FakePortProber = FakePortProber(), fetcher: FakeFetcher = FakeFetcher(),
                            checker: FakeChecker = FakeChecker(), clip: Clip = Clip()) -> IPScannerEnvironment {
        IPScannerEnvironment(
            interfaces: FakeInterfaces(list: interfaces), services: services, ports: ports, publicIP: fetcher, localNetwork: checker,
            copyToPasteboard: { text in MainActor.assumeIsolated { clip.copied.append(text) } },
            saveCSV: { csv in MainActor.assumeIsolated { clip.saved.append(csv) }; return "scan.csv" },
            open: { url in MainActor.assumeIsolated { clip.opened.append(url) } })
    }

    static func waitUntil(timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}
