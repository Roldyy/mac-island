import Foundation
@testable import FanShared

/// In-memory SMC: reads and writes go to a dictionary. Never touches the real SMC.
/// Defaults mirror what the read-only probe saw on the M4 Pro (2 fans, flt RPM keys, ui8 mode).
final class FakeSMC: SMCReader, SMCWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [SMCKey: (SMCKeyInfo, [UInt8])] = [:]
    private(set) var writes: [(key: String, value: Double?)] = []
    private(set) var readCount = 0
    /// Keys whose writes throw.
    var failingWrites: Set<String> = []
    /// Keys whose writes are accepted but silently dropped (value does not change).
    var ignoredWrites: Set<String> = []

    init(fans: Int = 2, min: Float = 2317, max: Float = 7826, actual: Float = 2400, withUnlock: Bool = true) {
        setRaw("FNum", .ui8, [UInt8(fans)])
        for i in 0..<fans {
            setFloat("F\(i)Ac", actual)
            setFloat("F\(i)Mn", min)
            setFloat("F\(i)Mx", max)
            setFloat("F\(i)Tg", min)
            setRaw("F\(i)Md", .ui8, [0])
        }
        if withUnlock { setRaw("Ftst", .ui8, [0]) }
    }

    func setFloat(_ name: String, _ value: Float) {
        let bits = value.bitPattern
        setRaw(name, .flt, [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> UInt32($0)) })
    }

    func setRaw(_ name: String, _ type: SMCDataType, _ bytes: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        store[SMCKey(name)!] = (SMCKeyInfo(size: UInt32(bytes.count), type: type, attributes: 0xD0), bytes)
    }

    func remove(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        store[SMCKey(name)!] = nil
    }

    func number(_ name: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard let (info, bytes) = store[SMCKey(name)!] else { return nil }
        return SMCCodec.decode(bytes, type: info.type)
    }

    func clearWrites() {
        lock.lock(); defer { lock.unlock() }
        writes.removeAll()
    }

    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        lock.lock(); defer { lock.unlock() }
        guard let (info, _) = store[key] else { throw SMCError.keyNotFound(key.description) }
        return info
    }

    func read(_ key: SMCKey) throws -> SMCValue {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        guard let (info, bytes) = store[key] else { throw SMCError.keyNotFound(key.description) }
        return SMCValue(key: key, info: info, bytes: bytes)
    }

    func write(_ key: SMCKey, bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        guard let (info, _) = store[key] else { throw SMCError.keyNotFound(key.description) }
        writes.append((key.description, SMCCodec.decode(bytes, type: info.type)))
        if failingWrites.contains(key.description) { throw SMCError.smcResult(0x85) }
        if ignoredWrites.contains(key.description) { return }
        store[key] = (info, bytes)
    }
}

/// Reader that refuses every write by not being a writer, used to prove read-only paths.
final class ReadOnlyFake: SMCReader, @unchecked Sendable {
    let inner = FakeSMC()
    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo { try inner.keyInfo(key) }
    func read(_ key: SMCKey) throws -> SMCValue { try inner.read(key) }
}

final class FakeClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval
    init(_ start: TimeInterval = 1000) { value = start }
    func now() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}

/// Mutable thermal input for the core.
final class ThermalBox: @unchecked Sendable {
    var snapshot = ThermalSnapshot(maxCelsius: 60, pressure: .nominal)
}
