import FanShared
import Foundation
import IOKit

/// The only SMC writer in the project. Exists only in the root helper target, is only called by
/// `FanControlCore` after `FanSafetyPolicy`, and refuses every key outside
/// `FanSMCKeys.isWritable` (`Ftst`, `F<n>Md`, `F<n>Tg`) and any byte count that does not match
/// the key's size.
///
/// COMPILE-ONLY: never instantiated outside the launchd daemon, never run during development.
/// Whether the SMC accepts these writes on an M4 Pro (and whether root is enough) is UNKNOWN.
///
/// Call made per write: key-info (`data8 = 9`) to check the size, then
/// `IOConnectCallStructMethod(connection, 2, ...)` with `data8 = 6` (write bytes),
/// `key`, `keyInfo.dataSize = bytes.count` and `bytes`.
final class AppleSMCWriter: SMCWriter, @unchecked Sendable {
    private enum Command: UInt8 {
        case writeBytes = 6
        case readKeyInfo = 9
    }

    private static let userClientSelector: UInt32 = 2
    private let lock = NSLock()
    private var connection: io_connect_t = 0

    init() throws {
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

    func write(_ key: SMCKey, bytes: [UInt8]) throws {
        guard FanSMCKeys.isWritable(key) else { throw SMCError.unsupportedValue("write refused: \(key)") }
        guard !bytes.isEmpty, bytes.count <= SMCParamStruct.bytesCount else { throw SMCError.unsupportedValue("size") }
        lock.lock(); defer { lock.unlock() }

        var infoRequest = SMCParamStruct()
        infoRequest.key = key.code
        let info = try call(.readKeyInfo, infoRequest, key: key)
        guard Int(info.dataSize) == bytes.count else { throw SMCError.unsupportedValue("\(key) size \(info.dataSize)") }

        var request = SMCParamStruct()
        request.key = key.code
        request.dataSize = info.dataSize
        request.dataType = info.dataType
        for (i, b) in bytes.enumerated() { request.bytes[i] = b }
        _ = try call(.writeBytes, request, key: key)
    }

    private func call(_ command: Command, _ input: SMCParamStruct, key: SMCKey) throws -> SMCParamStruct {
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
        if out.result == smcResultKeyNotFound { throw SMCError.keyNotFound(key.description) }
        guard out.result == 0 else { throw SMCError.smcResult(out.result) }
        return out
    }
}
