import Foundation

/// An IPv4 address as one 32-bit number. Parsing is strict: four decimal parts, no sign, no leading zero, no spaces.
public struct IPv4Address: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let value: UInt32

    public init(_ value: UInt32) { self.value = value }

    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard (1...3).contains(part.utf8.count), part.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            if part.utf8.count > 1, part.utf8.first == 0x30 { return nil }
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            result = result << 8 | octet
        }
        self.value = result
    }

    public var octets: [UInt8] {
        [UInt8(value >> 24 & 255), UInt8(value >> 16 & 255), UInt8(value >> 8 & 255), UInt8(value & 255)]
    }

    public var description: String { octets.map(String.init).joined(separator: ".") }

    public static func < (a: Self, b: Self) -> Bool { a.value < b.value }

    /// 10/8, 172.16/12, 192.168/16 (RFC 1918).
    public var isPrivate: Bool {
        value >> 24 == 10 || value >> 20 == 0xAC1 || value >> 16 == 0xC0A8
    }
    /// 169.254/16 (RFC 3927).
    public var isLinkLocal: Bool { value >> 16 == 0xA9FE }
    public var isLoopback: Bool { value >> 24 == 127 }
    public var isMulticast: Bool { value >> 28 == 0xE }
    /// The only ranges this feature ever touches.
    public var isLocalScannable: Bool { isPrivate || isLinkLocal }
}
