import Foundation

/// A 48-bit hardware address. `arp` prints octets without leading zeros ("2:10:18:8:4:8c"), so parsing takes
/// one or two hex digits per octet and nothing else.
public struct MACAddress: Hashable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 6 else { return nil }
        self.bytes = bytes
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }
        var out: [UInt8] = []
        for part in parts {
            guard (1...2).contains(part.utf8.count), part.utf8.allSatisfy(Self.isHex), let byte = UInt8(part, radix: 16) else { return nil }
            out.append(byte)
        }
        self.bytes = out
    }

    private static func isHex(_ c: UInt8) -> Bool {
        (0x30...0x39).contains(c) || (0x41...0x46).contains(c) || (0x61...0x66).contains(c)
    }

    /// "aa:bb:cc:dd:ee:ff", always two lowercase digits.
    public var description: String { bytes.map { String(format: "%02x", $0) }.joined(separator: ":") }

    public var isBroadcast: Bool { bytes.allSatisfy { $0 == 0xFF } }
    public var isMulticast: Bool { bytes[0] & 1 == 1 }
    public var isZero: Bool { bytes.allSatisfy { $0 == 0 } }
    /// Bit 1 of the first octet: a random per-network address (private Wi-Fi address), so no vendor can be named.
    public var isLocallyAdministered: Bool { bytes[0] & 2 == 2 }

    /// The first three octets as "AABBCC", the key of the vendor table.
    public var ouiKey: String { bytes.prefix(3).map { String(format: "%02X", $0) }.joined() }
}
