import Foundation

/// The root helper's decision engine: every SMC write goes through here, after `FanSafetyPolicy`.
/// Lives in FanShared so it is unit-tested with fakes; the helper executable only adds XPC, the
/// IOKit writer and timers. Not thread-safe: the helper calls it from one serial queue.
///
/// Write sequence for manual mode (community-reported for M-series, UNKNOWN on M4 Pro):
/// `Ftst = 1` (only if the key exists and is not already 1), `F<n>Md = 1`, `F<n>Tg = rpm`,
/// then `F<n>Md` is read back and anything but manual is treated as a failed write.
/// Restore: `F<n>Md = 0` for every fan this core set or that reads manual (1), read back, then
/// `Ftst = 0` if it is not 0. A failed restore is retried on every `tick()` and blocks new manual
/// requests until it succeeds.
public final class FanControlCore {
    public let policy: FanSafetyPolicy
    public private(set) var watchdog: Watchdog
    public private(set) var manualFans: Set<Int> = []
    /// Client that set manual mode last. Only it can keep manual mode alive with heartbeats.
    public private(set) var owner: Int?
    public private(set) var restorePending = false
    public private(set) var lastRestoreReason: RestoreReason?

    private let reader: SMCReader
    private let writer: SMCWriter
    private let clock: MonotonicClock
    private let thermal: () -> ThermalSnapshot
    private var lastChange: [Int: TimeInterval] = [:]
    private var unlockWritten = false
    private var pendingReason: RestoreReason?
    private var knownFanCount = 0

    public init(reader: SMCReader, writer: SMCWriter, clock: MonotonicClock = SystemUptimeClock(),
                policy: FanSafetyPolicy = FanSafetyPolicy(),
                watchdogTimeout: TimeInterval = FanHelperContract.watchdogTimeout,
                thermal: @escaping () -> ThermalSnapshot) {
        self.reader = reader
        self.writer = writer
        self.clock = clock
        self.policy = policy
        self.thermal = thermal
        watchdog = Watchdog(timeout: watchdogTimeout)
        knownFanCount = (try? FanReadService.fanCount(reader)) ?? 0
    }

    public var isManualActive: Bool { !manualFans.isEmpty }

    // MARK: - Requests

    public func perform(_ command: FanCommand, client: Int) -> FanCommandResult {
        switch command {
        case .allAutomatic:
            return restoreAutomatic(.clientRequest)
                ? FanCommandResult(status: .automatic)
                : FanCommandResult(status: .failed, reason: "restorePending")
        case .automatic(let fan):
            return setAutomatic(fan: fan)
        case .setTarget(let fan, let rpm):
            return setTarget(fan: fan, rpm: rpm, client: client)
        }
    }

    @discardableResult
    public func heartbeat(client: Int) -> Bool {
        guard owner == client, isManualActive else { return false }
        return watchdog.heartbeat(now: clock.now())
    }

    /// Called every `FanHelperContract.tickInterval`. Returns the reason only when it restored
    /// automatic and the restore succeeded. A restore the SMC refuses returns nil and leaves
    /// `restorePending` set (retried on the next tick): the caller logs that as a failure.
    @discardableResult
    public func tick() -> RestoreReason? {
        let reason: RestoreReason
        if restorePending {
            reason = pendingReason ?? .writeFailed
        } else if watchdog.expired(now: clock.now()) {
            reason = .watchdog
        } else if isManualActive, policy.mustForceAutomatic(thermal()) {
            reason = .thermal
        } else {
            return nil
        }
        return restoreAutomatic(reason) ? reason : nil
    }

    /// XPC connection of `client` was invalidated or interrupted (app quit, crashed or was killed).
    public func clientDisconnected(_ client: Int) {
        guard owner == client else { return }
        if isManualActive || restorePending {
            restoreAutomatic(.disconnected)
        } else {
            owner = nil
        }
    }

    /// Run once when the helper starts: a previous helper may have died with a fan left manual.
    @discardableResult
    public func recoverAtStartup() -> Bool { restoreAutomatic(.startup) }

    // MARK: - Restore

    /// Puts every fan this core drove, and every fan reading manual, back to automatic. Writes
    /// nothing when nothing is manual. True when every write succeeded and read back automatic.
    @discardableResult
    public func restoreAutomatic(_ reason: RestoreReason) -> Bool {
        if let count = try? FanReadService.fanCount(reader) { knownFanCount = count }
        var ok = true
        for fan in Set(0..<knownFanCount).union(manualFans).sorted() {
            guard let modeKey = FanSMCKeys.mode(fan) else { continue }
            let current = FanReadService.number(reader, modeKey)
            guard manualFans.contains(fan) || current == FanModeValue.manual else { continue }
            do {
                try writeMode(FanModeValue.automatic, fan: fan)
            } catch {
                ok = false
                continue
            }
            if FanReadService.mode(reader, fan: fan) == .manual { ok = false } else { manualFans.remove(fan) }
        }
        if !restoreUnlock() { ok = false }

        lastRestoreReason = reason
        watchdog.disarm()
        if ok {
            manualFans.removeAll()
            owner = nil
            restorePending = false
            pendingReason = nil
        } else {
            restorePending = true
            pendingReason = reason
        }
        return ok
    }

    private func restoreUnlock() -> Bool {
        let value = FanReadService.number(reader, FanSMCKeys.unlock)
        let needsWrite = value.map { $0 != 0 } ?? unlockWritten
        guard needsWrite else {
            unlockWritten = false
            return true
        }
        do {
            let info = try reader.keyInfo(FanSMCKeys.unlock)
            guard let bytes = SMCCodec.encode(0, as: info) else { return false }
            try writer.write(FanSMCKeys.unlock, bytes: bytes)
            unlockWritten = false
            return true
        } catch {
            return false
        }
    }

    // MARK: - Manual

    private func setTarget(fan: Int, rpm: Double, client: Int) -> FanCommandResult {
        if restorePending, !restoreAutomatic(pendingReason ?? .writeFailed) {
            return FanCommandResult(status: .failed, fan: fan, reason: "restorePending")
        }
        let now = clock.now()
        let decision = policy.evaluate(fan: fan, requestedRPM: rpm, limits: FanReadService.rawLimits(reader),
                                       thermal: thermal(), lastChange: lastChange[fan], now: now)
        switch decision {
        case .reject(let why, let retryAfter):
            return FanCommandResult(status: .rejected, fan: fan, reason: why.rawValue, retryAfter: retryAfter)
        case .forceAutomatic:
            restoreAutomatic(.thermal)
            return FanCommandResult(status: .forcedAutomatic, fan: fan, reason: "thermal")
        case .apply(let fan, let target):
            // Recorded before writing, so a partial write is undone by the restore below.
            manualFans.insert(fan)
            do {
                try writeManual(fan: fan, rpm: target)
            } catch {
                restoreAutomatic(.writeFailed)
                let unsupported: Bool
                if case SMCError.unsupportedValue = error { unsupported = true } else { unsupported = false }
                return FanCommandResult(status: .failed, fan: fan, reason: unsupported ? "unsupportedKey" : "writeFailed")
            }
            guard FanReadService.mode(reader, fan: fan) == .manual else {
                restoreAutomatic(.writeFailed)
                return FanCommandResult(status: .failed, fan: fan, reason: "notConfirmed")
            }
            lastChange[fan] = now
            owner = client
            if !watchdog.heartbeat(now: now) { watchdog.arm(now: now) }
            return FanCommandResult(status: .applied, fan: fan, appliedRPM: target)
        }
    }

    private func setAutomatic(fan: Int) -> FanCommandResult {
        if let count = try? FanReadService.fanCount(reader) { knownFanCount = count }
        guard (0..<knownFanCount).contains(fan) || manualFans.contains(fan) else {
            return FanCommandResult(status: .rejected, fan: fan, reason: FanRejection.unknownFan.rawValue)
        }
        if manualFans.subtracting([fan]).isEmpty {
            return restoreAutomatic(.clientRequest)
                ? FanCommandResult(status: .automatic, fan: fan)
                : FanCommandResult(status: .failed, fan: fan, reason: "restorePending")
        }
        do {
            try writeMode(FanModeValue.automatic, fan: fan)
            manualFans.remove(fan)
            return FanCommandResult(status: .automatic, fan: fan)
        } catch {
            restoreAutomatic(.writeFailed)
            return FanCommandResult(status: .failed, fan: fan, reason: "writeFailed")
        }
    }

    private func writeManual(fan: Int, rpm: Double) throws {
        guard let targetKey = FanSMCKeys.target(fan) else { throw SMCError.unsupportedValue("fan \(fan)") }
        let targetInfo = try reader.keyInfo(targetKey)
        guard let targetBytes = SMCCodec.encode(rpm, as: targetInfo) else {
            throw SMCError.unsupportedValue("\(targetKey) \(targetInfo.type)")
        }
        if let unlockInfo = try? reader.keyInfo(FanSMCKeys.unlock),
           FanReadService.number(reader, FanSMCKeys.unlock) != 1 {
            guard let bytes = SMCCodec.encode(1, as: unlockInfo) else {
                throw SMCError.unsupportedValue("\(FanSMCKeys.unlock) \(unlockInfo.type)")
            }
            unlockWritten = true
            try writer.write(FanSMCKeys.unlock, bytes: bytes)
        }
        try writeMode(FanModeValue.manual, fan: fan)
        try writer.write(targetKey, bytes: targetBytes)
    }

    private func writeMode(_ value: Double, fan: Int) throws {
        guard let key = FanSMCKeys.mode(fan) else { throw SMCError.unsupportedValue("fan \(fan)") }
        let info = try reader.keyInfo(key)
        guard let bytes = SMCCodec.encode(value, as: info) else { throw SMCError.unsupportedValue("\(key) \(info.type)") }
        try writer.write(key, bytes: bytes)
    }

    // MARK: - Reads

    public func state() -> FanState {
        FanState(protocolVersion: FanHelperContract.protocolVersion,
                 fans: (try? FanReadService.readings(reader)) ?? [],
                 maxTemperatureCelsius: thermal().maxCelsius,
                 manualActive: isManualActive)
    }

    /// Reads only: goes through `FanSelfTest`, which has no writer.
    public func selfTestReadOnly() -> FanSelfTestReport {
        FanSelfTest.run(reader: reader, thermal: thermal())
    }
}
