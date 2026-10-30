import FanShared
import Foundation
import os

/// Called from `atexit`; set once the daemon exists. A C callback cannot capture context.
nonisolated(unsafe) var exitRestoreHook: (() -> Void)?

/// The root daemon: XPC listener, the 1 s tick (watchdog + thermal), signal handling, and the
/// one serial queue every `FanControlCore` call runs on.
///
/// Automatic mode is restored: on watchdog expiry (no heartbeat for 8 s), on thermal override,
/// when the owning client's connection is invalidated or interrupted, on SIGTERM / SIGINT /
/// SIGHUP, at `exit`, and at the next start after a crash (`recoverAtStartup`). A SIGKILL or a
/// crash of the helper itself cannot run code, but the daemon plist has `KeepAlive` =
/// `{SuccessfulExit = false}` and `ThrottleInterval` = 10: launchd relaunches a helper that died
/// on a signal or a non-zero exit within about 10 s, and `recoverAtStartup` restores automatic
/// without the app. Exit code 0 means "do not restart" (see `main.swift`).
final class HelperDaemon: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    /// While a restore keeps failing, the failure is logged at most this often (ticks are 1 s).
    private static let restoreFailureLogInterval: TimeInterval = 10

    let core: FanControlCore
    private let queue = DispatchQueue(label: "be.roldy.macisland.fanhelper.core")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let listener = NSXPCListener(machServiceName: FanHelperContract.machServiceName)
    private let logger = Logger(subsystem: FanHelperContract.machServiceName, category: "helper")
    private let clock = SystemUptimeClock()
    private var timer: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []
    private var nextClientID = 0
    /// Touched on `queue` only, like `core`.
    private var restoreFailureLog = LogThrottle(interval: HelperDaemon.restoreFailureLogInterval)

    init(reader: AppleSMCReadOnlyClient, writer: AppleSMCWriter) {
        let policy = FanSafetyPolicy()
        let sensors = TemperatureSensors(keys: TemperatureSensors.discover(reader.allKeys(),
                                                                           prefixes: TemperatureSensors.defaultPrefixes))
        core = FanControlCore(reader: reader, writer: writer, policy: policy) {
            ThermalSnapshot(maxCelsius: sensors.maxCelsius(reader, plausible: policy.plausibleCelsius),
                            pressure: ThermalPressure(ProcessInfo.processInfo.thermalState))
        }
        super.init()
        queue.setSpecific(key: queueKey, value: true)
        logger.notice("temperature keys watched: \(sensors.keys.count, privacy: .public)")
    }

    /// Runs `work` on the core queue, inline when already on it (signal handler -> exit -> atexit).
    func onQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return try work() }
        return try queue.sync(execute: work)
    }

    func start() {
        let recovered = onQueue { core.recoverAtStartup() }
        logger.notice("startup recovery: \(recovered ? "clean" : "restore pending", privacy: .public)")

        exitRestoreHook = { [self] in _ = onQueue { core.restoreAutomatic(.shutdown) } }
        atexit { exitRestoreHook?() }
        installSignalHandlers()
        startTicking()

        // macOS 13+: peers failing the requirement are rejected before the delegate is asked.
        listener.setConnectionCodeSigningRequirement(FanHelperContract.clientRequirement)
        listener.delegate = self
        listener.activate()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let id: Int = onQueue {
            nextClientID += 1
            return nextClientID
        }
        connection.exportedInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.exportedObject = HelperConnection(daemon: self, clientID: id)
        connection.invalidationHandler = { [weak self] in self?.disconnected(id) }
        connection.interruptionHandler = { [weak self] in self?.disconnected(id) }
        connection.activate()
        logger.notice("client \(id, privacy: .public) connected, uid \(connection.effectiveUserIdentifier, privacy: .public)")
        return true
    }

    func log(result: FanCommandResult, client: Int) {
        logger.notice("""
            client \(client, privacy: .public): \(result.status.rawValue, privacy: .public) \
            \(result.reason ?? "", privacy: .public)
            """)
    }

    private func disconnected(_ id: Int) {
        onQueue { core.clientDisconnected(id) }
        logger.notice("client \(id, privacy: .public) gone")
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler { [weak self] in
                guard let self else { exit(0) }
                let ok = self.core.restoreAutomatic(.shutdown)
                self.logger.notice("signal \(sig, privacy: .public): automatic \(ok ? "restored" : "FAILED", privacy: .public)")
                // atexit runs the restore again: idempotent, no SMC write when nothing is manual.
                // 0 = launchd does not restart; after a failed restore exit 1 so a still-loaded
                // job is relaunched and its startup recovery retries.
                exit(ok ? 0 : 1)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func startTicking() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + FanHelperContract.tickInterval,
                   repeating: FanHelperContract.tickInterval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if let reason = self.core.tick() {
                self.restoreFailureLog.reset()
                self.logger.notice("restored automatic: \(reason.rawValue, privacy: .public)")
            } else if self.core.restorePending {
                // The SMC refused the restore: fans may still be manual. Retried every tick,
                // logged once per 10 s.
                guard self.restoreFailureLog.allow(now: self.clock.now()) else { return }
                let reason = self.core.lastRestoreReason?.rawValue ?? "unknown"
                self.logger.error("restore FAILED (\(reason, privacy: .public)): fans may still be manual, retrying every second")
            } else {
                self.restoreFailureLog.reset()   // the next failure, if any, is logged at once
            }
        }
        t.resume()
        timer = t
    }
}
