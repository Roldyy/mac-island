import Foundation

public struct PortScanConfiguration: Equatable, Sendable {
    public var concurrency = 8
    public var timeout: Duration = .milliseconds(800)
    /// Minimum gap between two connection starts: about 40 attempts a second at most.
    public var minInterval: Duration = .milliseconds(25)

    public init(concurrency: Int = 8, timeout: Duration = .milliseconds(800), minInterval: Duration = .milliseconds(25)) {
        self.concurrency = min(max(concurrency, 1), 16)
        self.timeout = timeout
        self.minInterval = minInterval
    }
}

/// A port scan of ONE chosen host over the preset list. The host must be a real host of an active local subnet and the
/// ports are cut down to the presets before anything is sent. Started by a click, never automatically.
public enum PortScanEngine {
    public static func run(host: IPv4Address, ports requested: some Collection<UInt16>, subnets: [IPv4Subnet],
                           configuration: PortScanConfiguration = PortScanConfiguration(), prober: any PortProbing,
                           progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [UInt16] {
        try ScanPlanner.validateHost(host, in: subnets)
        let ports = PortPreset.sanitized(requested)
        guard !ports.isEmpty else { return [] }
        let timeout = configuration.timeout
        var open: [UInt16] = []
        var done = 0
        try await BoundedRunner.forEach(ports, limit: configuration.concurrency, spacing: configuration.minInterval,
                                        work: { await prober.isOpen(host: host, port: $0, timeout: timeout) }) { port, isOpen in
            done += 1
            if isOpen { open.append(port) }
            progress(done, ports.count)
        }
        return open.sorted()
    }
}
