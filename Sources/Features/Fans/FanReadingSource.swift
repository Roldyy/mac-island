import FanShared
import Foundation

/// Where the monitoring section reads fans from. Works without the helper.
protocol FanReadingSource: Sendable {
    func readFans() throws -> [FanReading]
}

/// Reads the SMC in user space through `AppleSMCReadOnlyClient` (no write command exists in it).
/// Verified on the M4 Pro: an unprivileged process reads FNum and F0/F1 Ac, Mn, Mx, Md, Tg.
/// The SMC connection opens on the first read, so building the tab touches nothing.
final class SMCFanReadingSource: FanReadingSource, @unchecked Sendable {
    private let lock = NSLock()
    private var client: AppleSMCReadOnlyClient?

    func readFans() throws -> [FanReading] {
        lock.lock(); defer { lock.unlock() }
        if client == nil { client = try AppleSMCReadOnlyClient() }
        guard let client else { throw SMCError.serviceNotFound }
        return try FanReadService.readings(client)
    }
}
