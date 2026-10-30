import Foundation

/// Byte decoding and encoding of SMC values. Integers and fixed-point are big-endian; `flt ` is a
/// little-endian IEEE float on Apple silicon (verified by reading F0Mn/F0Mx on this Mac, see the
/// lane report). Anything not listed is refused: an unknown encoding is never guessed.
public enum SMCCodec {
    public static func decode(_ bytes: [UInt8], type: SMCDataType) -> Double? {
        switch type {
        case .flt:
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case .ui8, .flag:
            guard let first = bytes.first else { return nil }
            return Double(first)
        case .ui16:
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case .ui32:
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case .fpe2:
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case .sp78:
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    /// Bytes to write for `value` into a key described by `info`, or nil when the value does not fit
    /// the type exactly (non-finite, out of range, fractional for an integer, size mismatch).
    public static func encode(_ value: Double, as info: SMCKeyInfo) -> [UInt8]? {
        guard value.isFinite else { return nil }
        switch info.type {
        case .flt:
            guard info.size == 4 else { return nil }
            let float = Float(value)
            guard float.isFinite else { return nil }
            let bits = float.bitPattern
            return [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> UInt32($0)) }
        case .ui8:
            guard info.size == 1, value == value.rounded(), (0...255).contains(value) else { return nil }
            return [UInt8(value)]
        case .ui16:
            guard info.size == 2, value == value.rounded(), (0...65_535).contains(value) else { return nil }
            let v = UInt16(value)
            return [UInt8(v >> 8), UInt8(v & 0xFF)]
        case .fpe2:
            guard info.size == 2, (0...16_383.75).contains(value) else { return nil }
            let v = UInt16((value * 4).rounded())
            return [UInt8(v >> 8), UInt8(v & 0xFF)]
        default:
            return nil
        }
    }
}
