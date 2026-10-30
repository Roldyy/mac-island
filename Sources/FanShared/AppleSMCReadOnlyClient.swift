import Foundation
import IOKit

/// Read-only access to the AppleSMC user client. It can express three commands only (read bytes,
/// read key by index, read key info): there is no write command in this type, by construction.
/// The writer is a separate type that exists only in the root helper target.
///
/// Calls made: `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))`,
/// `IOServiceOpen(service, mach_task_self_, 0, &connection)`, then
/// `IOConnectCallStructMethod(connection, 2, in, 80, out, &80)` with `data8` set to the command.
public final class AppleSMCReadOnlyClient: SMCReader, @unchecked Sendable {
    public enum ReadCommand: UInt8, CaseIterable, Sendable {
        case readBytes = 5
        case readIndex = 8
        case readKeyInfo = 9
    }

    /// AppleSMC user-client method used by every open-source SMC tool for all commands.
    static let userClientSelector: UInt32 = 2

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var infoCache: [SMCKey: SMCKeyInfo] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw SMCError.openFailed(kr) }
        connection = conn
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        lock.lock(); defer { lock.unlock() }
        return try cachedInfo(key)
    }

    public func read(_ key: SMCKey) throws -> SMCValue {
        lock.lock(); defer { lock.unlock() }
        let info = try cachedInfo(key)
        var input = SMCParamStruct()
        input.key = key.code
        input.dataSize = info.size
        let out = try call(.readBytes, input, key: key)
        let count = min(Int(info.size), SMCParamStruct.bytesCount)
        return SMCValue(key: key, info: info, bytes: Array(out.bytes.prefix(count)))
    }

    /// Number of keys the SMC exposes (`#KEY`).
    public func keyCount() throws -> Int {
        guard let countKey = SMCKey("#KEY"), let n = try read(countKey).number else { throw SMCError.invalidResponse }
        return Int(n)
    }

    /// The key at `index` in the SMC's own key table (enumeration, read-only).
    public func key(at index: Int) throws -> SMCKey {
        lock.lock(); defer { lock.unlock() }
        var input = SMCParamStruct()
        input.data32 = UInt32(clamping: index)
        let out = try call(.readIndex, input, key: nil)
        return SMCKey(code: out.key)
    }

    /// Every key name the SMC lists (about 3,200 on the M4 Pro, 0.7 s). Read-index only.
    public func allKeys() -> [SMCKey] {
        guard let count = try? keyCount(), count > 0 else { return [] }
        return (0..<count).compactMap { try? key(at: $0) }
    }

    private func cachedInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        if let cached = infoCache[key] { return cached }
        var input = SMCParamStruct()
        input.key = key.code
        let out = try call(.readKeyInfo, input, key: key)
        let info = SMCKeyInfo(size: out.dataSize, type: SMCDataType(code: out.dataType), attributes: out.dataAttributes)
        infoCache[key] = info
        return info
    }

    private func call(_ command: ReadCommand, _ input: SMCParamStruct, key: SMCKey?) throws -> SMCParamStruct {
        var request = input
        request.data8 = command.rawValue
        let inBytes = request.encoded()
        var outBytes = [UInt8](repeating: 0, count: SMCParamStruct.size)
        var outSize = SMCParamStruct.size
        let kr = inBytes.withUnsafeBytes { inPtr in
            outBytes.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, Self.userClientSelector,
                                          inPtr.baseAddress, SMCParamStruct.size,
                                          outPtr.baseAddress, &outSize)
            }
        }
        guard kr == KERN_SUCCESS else { throw SMCError.callFailed(kr) }
        guard let out = SMCParamStruct(decoding: outBytes) else { throw SMCError.invalidResponse }
        if out.result == smcResultKeyNotFound { throw SMCError.keyNotFound(key?.description ?? "#\(input.data32)") }
        guard out.result == 0 else { throw SMCError.smcResult(out.result) }
        return out
    }
}
