import Foundation

/// A four-character SMC key such as `F0Ac`, stored the way the SMC expects it: big-endian ASCII.
public struct SMCKey: Hashable, Sendable, CustomStringConvertible {
    public let code: UInt32

    /// Exactly four printable ASCII characters, otherwise nil.
    public init?(_ name: String) {
        guard let code = FourCharCode.parse(name) else { return nil }
        self.code = code
    }

    public init(code: UInt32) { self.code = code }

    public var description: String { FourCharCode.render(code) }
}

/// The SMC data type of a key, e.g. `flt `, `ui8 `, `fpe2`.
public struct SMCDataType: Hashable, Sendable, CustomStringConvertible {
    public let code: UInt32

    public init?(_ name: String) {
        guard let code = FourCharCode.parse(name) else { return nil }
        self.code = code
    }

    public init(code: UInt32) { self.code = code }

    public var description: String { FourCharCode.render(code) }

    public static let flt = SMCDataType(code: 0x666C_7420)   // "flt "
    public static let ui8 = SMCDataType(code: 0x7569_3820)   // "ui8 "
    public static let ui16 = SMCDataType(code: 0x7569_3136)  // "ui16"
    public static let ui32 = SMCDataType(code: 0x7569_3332)  // "ui32"
    public static let fpe2 = SMCDataType(code: 0x6670_6532)  // "fpe2"
    public static let sp78 = SMCDataType(code: 0x7370_3738)  // "sp78"
    public static let flag = SMCDataType(code: 0x666C_6167)  // "flag"
}

/// What the key-info call returns for a key.
public struct SMCKeyInfo: Equatable, Sendable {
    public var size: UInt32
    public var type: SMCDataType
    /// Raw attribute byte. Its bit meanings on Apple silicon are UNKNOWN; reported, never relied on.
    public var attributes: UInt8

    public init(size: UInt32, type: SMCDataType, attributes: UInt8) {
        self.size = size
        self.type = type
        self.attributes = attributes
    }
}

/// A raw read: the key, its info and the meaningful bytes (`info.size` of them).
public struct SMCValue: Equatable, Sendable {
    public var key: SMCKey
    public var info: SMCKeyInfo
    public var bytes: [UInt8]

    public init(key: SMCKey, info: SMCKeyInfo, bytes: [UInt8]) {
        self.key = key
        self.info = info
        self.bytes = bytes
    }

    public var number: Double? { SMCCodec.decode(bytes, type: info.type) }
}

enum FourCharCode {
    static func parse(_ name: String) -> UInt32? {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count == 4,
              scalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) else { return nil }
        return scalars.reduce(UInt32(0)) { ($0 << 8) | $1.value }
    }

    static func render(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> UInt32($0)) }
        let printable = bytes.map { $0 >= 0x20 && $0 < 0x7F ? Character(UnicodeScalar($0)) : "?" }
        return String(printable)
    }
}
