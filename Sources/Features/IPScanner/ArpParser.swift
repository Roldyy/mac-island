import Foundation

/// One resolved neighbour from the ARP table.
public struct ArpEntry: Equatable, Sendable {
    public let ip: IPv4Address
    public let mac: MACAddress
    public let interface: String
}

/// Reads the output of `arp -an` and keeps only well-formed, resolved, unicast entries.
///
/// Strict and bounded: the input is cut at `maxBytes`, at most `maxLines` lines and `maxLineLength` bytes per line are
/// looked at, and a line must match `? (A.B.C.D) at M on IFACE ...` exactly. Anything else is dropped, never repaired.
/// `arp -an` always prints `?` as the name, so anything else there is refused; the only things taken from a line are an IPv4, a MAC and an interface name.
public enum ArpParser {
    public static let maxBytes = 1 << 20
    public static let maxLines = 4096
    public static let maxLineLength = 256
    public static let maxInterfaceNameLength = 16

    public static func parse(_ data: Data) -> [ArpEntry] {
        parse(String(decoding: data.prefix(maxBytes), as: UTF8.self))
    }

    public static func parse(_ text: String) -> [ArpEntry] {
        var entries: [ArpEntry] = []
        var seen = Set<IPv4Address>()
        var lines = 0
        for rawLine in text.utf8.split(separator: 0x0A, omittingEmptySubsequences: true) {
            lines += 1
            if lines > maxLines { break }
            guard rawLine.count <= maxLineLength, let entry = parseLine(Substring(String(decoding: rawLine, as: UTF8.self))),
                  seen.insert(entry.ip).inserted else { continue }
            entries.append(entry)
        }
        return entries
    }

    static func parseLine(_ line: Substring) -> ArpEntry? {
        // "? (192.168.0.1) at 2:10:18:8:4:8c on en0 ifscope [ethernet]" -- host, "(ip)", "at", mac, "on", iface, flags...
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count >= 6, tokens[0] == "?", tokens[2] == "at", tokens[4] == "on" else { return nil }
        let ipToken = tokens[1]
        guard ipToken.hasPrefix("("), ipToken.hasSuffix(")"), let ip = IPv4Address(String(ipToken.dropFirst().dropLast())),
              let mac = MACAddress(String(tokens[3])) else { return nil }
        let interface = String(tokens[5])
        guard isInterfaceName(interface) else { return nil }
        // A neighbour is a unicast host: no broadcast, multicast or all-zero hardware address, no multicast IP.
        guard !mac.isBroadcast, !mac.isMulticast, !mac.isZero, !ip.isMulticast, !ip.isLoopback, ip.value != 0xFFFF_FFFF else { return nil }
        return ArpEntry(ip: ip, mac: mac, interface: interface)
    }

    static func isInterfaceName(_ name: String) -> Bool {
        guard (1...maxInterfaceNameLength).contains(name.utf8.count) else { return false }
        return name.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2E || $0 == 0x5F || $0 == 0x2D }
    }
}
