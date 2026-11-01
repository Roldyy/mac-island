import Foundation

public struct ScanConfiguration: Equatable, Sendable {
    public static let concurrencyRange = 8...128
    public static let timeoutRangeMs = 200...3000

    public var concurrency = 64
    public var timeout: Duration = .milliseconds(800)
    public var resolveNames = true
    public var useBonjour = true
    public var nameConcurrency = 16

    public init() {}

    /// The limits the settings cannot exceed, applied again by the engine.
    public var clamped: ScanConfiguration {
        var copy = self
        copy.concurrency = min(max(concurrency, Self.concurrencyRange.lowerBound), Self.concurrencyRange.upperBound)
        copy.nameConcurrency = min(max(nameConcurrency, 1), 32)
        return copy
    }
}

public struct ScanProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case probing, readingTable, naming }
    public var done: Int
    public var total: Int
    public var found: Int
    public var phase: Phase

    public var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 1 }
}

/// What the engine needs from the interface it scans on.
public struct ScanContext: Equatable, Sendable {
    public let subnet: IPv4Subnet
    public let selfAddress: IPv4Address
    public let gateway: IPv4Address?

    public init(subnet: IPv4Subnet, selfAddress: IPv4Address, gateway: IPv4Address?) {
        self.subnet = subnet
        self.selfAddress = selfAddress
        self.gateway = gateway
    }

    public init(_ interface: LocalInterface) {
        self.init(subnet: interface.subnet, selfAddress: interface.address, gateway: interface.gateway)
    }
}

public struct ScanServices: Sendable {
    public var nudger: any HostNudging
    public var neighbors: any NeighborTableReading
    public var resolver: any NameResolving
    public var discovery: any ServiceDiscovering
    public var oui: OUITable

    public init(nudger: any HostNudging, neighbors: any NeighborTableReading, resolver: any NameResolving,
                discovery: any ServiceDiscovering, oui: OUITable = .bundled) {
        self.nudger = nudger
        self.neighbors = neighbors
        self.resolver = resolver
        self.discovery = discovery
        self.oui = oui
    }

    public static let live = ScanServices(nudger: TCPHostNudger(), neighbors: ArpTableReader(),
                                          resolver: SystemNameResolver(), discovery: BonjourDiscovery())
}

/// The scan itself: nudge every target (bounded), read the ARP table once, add names and vendors.
/// Every target is checked against the interface's own subnet again here, so no caller can widen a scan.
public enum ScanEngine {
    public static let bonjourWindow: Duration = .seconds(3)

    public static func run(targets: [IPv4Address], context: ScanContext, configuration: ScanConfiguration,
                           services: ScanServices,
                           progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async throws -> [DeviceRecord] {
        guard context.subnet.network.isLocalScannable else { throw ScanRefusal.interfaceNotLocal }
        guard targets.allSatisfy({ context.subnet.contains($0) && $0.isLocalScannable }) else { throw ScanRefusal.outsideInterfaceSubnet }
        let config = configuration.clamped
        let targetSet = Set(targets)
        let total = targets.count
        try Task.checkCancellation()

        async let discovered: ServiceDiscovery = config.useBonjour
            ? services.discovery.discover(within: bonjourWindow, limit: 64) : ServiceDiscovery()

        var latencies: [IPv4Address: Double] = [:]
        var done = 0
        let nudger = services.nudger
        let timeout = config.timeout
        try await BoundedRunner.forEach(targets, limit: config.concurrency, work: { await nudger.nudge($0, timeout: timeout) }) { ip, outcome in
            done += 1
            if case .answered(let ms) = outcome { latencies[ip] = ms }
            progress(ScanProgress(done: done, total: total, found: latencies.count, phase: .probing))
        }
        try Task.checkCancellation()

        progress(ScanProgress(done: total, total: total, found: latencies.count, phase: .readingTable))
        let entries = await services.neighbors.read()
        try Task.checkCancellation()

        var byIP: [IPv4Address: DeviceRecord] = [:]
        for entry in entries where targetSet.contains(entry.ip) {
            byIP[entry.ip] = DeviceRecord(ip: entry.ip, mac: entry.mac, vendor: services.oui.vendor(of: entry.mac),
                                          latencyMs: latencies[entry.ip])
        }
        for (ip, ms) in latencies where byIP[ip] == nil { byIP[ip] = DeviceRecord(ip: ip, latencyMs: ms) }
        if targetSet.contains(context.selfAddress) {
            var me = byIP[context.selfAddress] ?? DeviceRecord(ip: context.selfAddress)
            me.isThisMac = true
            byIP[context.selfAddress] = me
        }
        if let gateway = context.gateway, var router = byIP[gateway] {
            router.isGateway = true
            byIP[gateway] = router
        }

        let bonjourNames = await discovered
        for (ip, name) in bonjourNames.names where byIP[ip] != nil { byIP[ip]?.serviceName = DisplayText.clean(name) }

        if config.resolveNames {
            let resolver = services.resolver
            let addresses = byIP.keys.sorted()
            var named = 0
            try await BoundedRunner.forEach(addresses, limit: config.nameConcurrency, work: { await resolver.hostName(for: $0) }) { ip, name in
                named += 1
                byIP[ip]?.hostName = DisplayText.clean(name)
                progress(ScanProgress(done: named, total: addresses.count, found: byIP.count, phase: .naming))
            }
        }
        return byIP.values.sorted { $0.ip < $1.ip }
    }
}
