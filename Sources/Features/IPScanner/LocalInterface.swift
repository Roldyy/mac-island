import Darwin
import Foundation
import SystemConfiguration

/// An active IPv4 interface the scan may start from.
public struct LocalInterface: Equatable, Identifiable, Sendable {
    public let name: String
    public let address: IPv4Address
    public let subnet: IPv4Subnet
    public let gateway: IPv4Address?

    public var id: String { name }
    public var netmask: IPv4Address { subnet.netmask }
    /// Only a private or link-local interface can be scanned.
    public var isScannable: Bool { subnet.network.isLocalScannable }

    public init(name: String, address: IPv4Address, subnet: IPv4Subnet, gateway: IPv4Address? = nil) {
        self.name = name
        self.address = address
        self.subnet = subnet
        self.gateway = gateway
    }
}

public protocol InterfaceProviding: Sendable {
    func interfaces() -> [LocalInterface]
}

/// Reads the interfaces with `getifaddrs` and the default gateway from the system configuration store. Neither
/// sends a packet nor needs a permission.
public struct SystemInterfaceProvider: InterfaceProviding {
    /// Tunnels, AirDrop, low-latency Wi-Fi and similar virtual interfaces are never a place to scan.
    static let ignoredPrefixes = ["lo", "utun", "awdl", "llw", "ap", "anpi", "gif", "stf", "XHC", "pktap"]

    public init() {}

    public func interfaces() -> [LocalInterface] {
        let (primaryName, router) = Self.defaultRoute()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [LocalInterface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let maskPtr = entry.pointee.ifa_netmask else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !Self.ignoredPrefixes.contains(where: name.hasPrefix) else { continue }
            let ip = Self.address(of: addr)
            let mask = Self.address(of: maskPtr)
            guard let subnet = IPv4Subnet(address: ip, mask: mask), !ip.isLoopback else { continue }
            let gateway = (name == primaryName ? router : nil).flatMap { subnet.contains($0) ? $0 : nil }
            found.append(LocalInterface(name: name, address: ip, subnet: subnet, gateway: gateway))
        }
        // The primary interface first, then by name.
        return found.sorted { ($0.name == primaryName ? 0 : 1, $0.name) < ($1.name == primaryName ? 0 : 1, $1.name) }
    }

    private static func address(of sockaddrPointer: UnsafePointer<sockaddr>) -> IPv4Address {
        sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { IPv4Address(UInt32(bigEndian: $0.pointee.sin_addr.s_addr)) }
    }

    private static func defaultRoute() -> (interface: String?, router: IPv4Address?) {
        guard let store = SCDynamicStoreCreate(nil, "MacIsland.IPScanner" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return (nil, nil) }
        let router = (value["Router"] as? String).flatMap { IPv4Address($0) }
        return (value["PrimaryInterface"] as? String, router)
    }
}
