import Foundation

// The doors the scan goes through. Everything that touches the network sits behind one of these protocols, so the
// engine and the model are tested with fakes and the live types below never run in a test.

public enum NudgeOutcome: Equatable, Sendable {
    /// The host answered at the TCP level (a connection, or a refusal): it is there. Latency in milliseconds.
    case answered(latencyMs: Double)
    case silent
}

/// Makes the Mac talk to one address so the system resolves it and fills the ARP table.
public protocol HostNudging: Sendable {
    func nudge(_ ip: IPv4Address, timeout: Duration) async -> NudgeOutcome
}

/// A single TCP connect, to decide whether one port of one host is open.
public protocol PortProbing: Sendable {
    func isOpen(host: IPv4Address, port: UInt16, timeout: Duration) async -> Bool
}

public protocol NameResolving: Sendable {
    /// Reverse DNS (and the system's mDNS reverse lookup) for one address; nil when there is no name.
    func hostName(for ip: IPv4Address) async -> String?
}

public protocol NeighborTableReading: Sendable {
    func read() async -> [ArpEntry]
}

public struct ServiceDiscovery: Equatable, Sendable {
    public var names: [IPv4Address: String]
    /// The system refused local network access to the Bonjour browser.
    public var policyDenied: Bool
    public init(names: [IPv4Address: String] = [:], policyDenied: Bool = false) {
        self.names = names
        self.policyDenied = policyDenied
    }
}

public protocol ServiceDiscovering: Sendable {
    func discover(within: Duration, limit: Int) async -> ServiceDiscovery
}

/// Runs one fixed program with a fixed argument vector. No shell, no interpolation.
public protocol ArgvRunning: Sendable {
    /// The program's standard output, cut at `maxBytes`; nil when it could not run, timed out or failed.
    func run(path: String, arguments: [String], maxBytes: Int, timeout: Duration) async -> Data?
}

public protocol PublicIPFetching: Sendable {
    func fetch(from url: URL) async throws -> String
}

public protocol LocalNetworkChecking: Sendable {
    /// One first local connection to `target`; this is what makes macOS ask (once) for local network access.
    func check(target: IPv4Address) async -> LocalNetworkState
}

public enum LocalNetworkState: Equatable, Sendable {
    case unknown, granted, denied
}
