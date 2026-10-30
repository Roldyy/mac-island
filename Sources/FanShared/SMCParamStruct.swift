import Foundation

/// The 80-byte argument of the AppleSMC user-client call (selector 2), laid out at explicit offsets
/// to match the C struct used by every open-source SMC tool (`SMCKeyData_t`):
///
///     0  UInt32 key
///     4  vers        { char major, minor, build, reserved; UInt16 release }      (6 bytes)
///    12  pLimitData  { UInt16 version, length; UInt32 cpu, gpu, mem }           (16 bytes)
///    28  keyInfo     { UInt32 dataSize; UInt32 dataType; char dataAttributes }  (12 bytes, padded)
///    40  char result, 41 char status, 42 char data8 (the command), 43 pad
///    44  UInt32 data32 (key index for the read-index command)
///    48  char bytes[32]
///
/// Explicit offsets instead of a Swift struct: a nested Swift struct is placed at its size, not its
/// stride, so `result` would land at 37 instead of 40. Integers are in host order (little-endian).
public struct SMCParamStruct: Equatable, Sendable {
    public static let size = 80
    public static let bytesCount = 32

    public var key: UInt32 = 0
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes = [UInt8](repeating: 0, count: SMCParamStruct.bytesCount)

    public init() {}

    public init?(decoding raw: [UInt8]) {
        guard raw.count >= Self.size else { return nil }
        key = Self.u32(raw, 0)
        dataSize = Self.u32(raw, 28)
        dataType = Self.u32(raw, 32)
        dataAttributes = raw[36]
        result = raw[40]
        status = raw[41]
        data8 = raw[42]
        data32 = Self.u32(raw, 44)
        bytes = Array(raw[48..<80])
    }

    public func encoded() -> [UInt8] {
        var raw = [UInt8](repeating: 0, count: Self.size)
        Self.put(key, into: &raw, at: 0)
        Self.put(dataSize, into: &raw, at: 28)
        Self.put(dataType, into: &raw, at: 32)
        raw[36] = dataAttributes
        raw[40] = result
        raw[41] = status
        raw[42] = data8
        Self.put(data32, into: &raw, at: 44)
        for (i, b) in bytes.prefix(Self.bytesCount).enumerated() { raw[48 + i] = b }
        return raw
    }

    private static func u32(_ raw: [UInt8], _ offset: Int) -> UInt32 {
        raw[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private static func put(_ value: UInt32, into raw: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { for (i, b) in $0.enumerated() { raw[offset + i] = b } }
    }
}

/// SMC result byte for a key that does not exist (`kSMCKeyNotFound`).
public let smcResultKeyNotFound: UInt8 = 0x84

public enum SMCError: Error, Equatable, Sendable {
    case serviceNotFound
    case openFailed(Int32)
    case callFailed(Int32)
    case keyNotFound(String)
    case smcResult(UInt8)
    case unsupportedValue(String)
    case invalidResponse
}
