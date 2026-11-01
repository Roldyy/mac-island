import Foundation

/// An IPv4 network: a base address and a prefix length (0...32). The base is always masked, so two
/// subnets built from different hosts of one network are equal.
public struct IPv4Subnet: Hashable, Sendable, CustomStringConvertible {
    public let network: IPv4Address
    public let prefix: Int

    public init?(address: IPv4Address, prefix: Int) {
        guard (0...32).contains(prefix) else { return nil }
        self.prefix = prefix
        self.network = IPv4Address(address.value & Self.mask(prefix))
    }

    /// `mask` must be contiguous ones followed by zeros (255.255.255.0); anything else is refused.
    public init?(address: IPv4Address, mask: IPv4Address) {
        guard let prefix = Self.prefix(ofMask: mask) else { return nil }
        self.init(address: address, prefix: prefix)
    }

    /// "192.168.1.0/24"; a bare address is a /32.
    public init?(cidr: String) {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, let address = IPv4Address(String(parts[0])) else { return nil }
        if parts.count == 1 { self.init(address: address, prefix: 32); return }
        guard (1...2).contains(parts[1].utf8.count), parts[1].utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
              let prefix = Int(parts[1]) else { return nil }
        self.init(address: address, prefix: prefix)
    }

    static func mask(_ prefix: Int) -> UInt32 { prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix) }

    static func prefix(ofMask mask: IPv4Address) -> Int? {
        let ones = mask.value.nonzeroBitCount
        return Self.mask(ones) == mask.value ? ones : nil
    }

    public var netmask: IPv4Address { IPv4Address(Self.mask(prefix)) }
    public var broadcast: IPv4Address { IPv4Address(network.value | ~Self.mask(prefix)) }
    public var description: String { "\(network)/\(prefix)" }

    public func contains(_ address: IPv4Address) -> Bool { address.value & Self.mask(prefix) == network.value }

    public func contains(_ other: IPv4Subnet) -> Bool { other.prefix >= prefix && contains(other.network) }

    /// Number of addresses a scan visits: /32 is 1, /31 is 2 (RFC 3021), otherwise network and broadcast are not hosts.
    public var hostCount: Int {
        switch prefix {
        case 32: 1
        case 31: 2
        default: (1 << (32 - prefix)) - 2
        }
    }

    public var firstHost: IPv4Address { prefix >= 31 ? network : IPv4Address(network.value + 1) }
    public var lastHost: IPv4Address { prefix >= 31 ? broadcast : IPv4Address(broadcast.value - 1) }

    public func isHost(_ address: IPv4Address) -> Bool { contains(address) && address >= firstHost && address <= lastHost }

    /// Every scanned address, in order. Only call it after `ScanPlanner` bounded the size.
    public func hosts() -> [IPv4Address] {
        guard hostCount > 0 else { return [] }
        return (firstHost.value...lastHost.value).map(IPv4Address.init)
    }
}
