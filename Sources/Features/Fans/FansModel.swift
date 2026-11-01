import FanShared
import Foundation
import Observation

/// State of the Fans tab. Monitoring reads the SMC directly (no helper); manual control goes
/// through the root helper and is available only when it is approved and reachable.
///
/// Manual mode outlives the view: closing the island or the tab keeps the fans forced, and the
/// heartbeat is a model-level timer that runs while manual is active, whatever is on screen.
/// Manual mode ends on: "Retour automatique", `stop()` (app quit), the model's release
/// (`ManualReleaseGuard`), a refused heartbeat (the helper's thermal override or watchdog), or
/// the connection dropping. If the app crashes or hangs, none of that runs: the helper's
/// watchdog (8 s without heartbeat) and its connection-invalidation handler restore automatic.
@MainActor
@Observable
final class FansModel {
    private(set) var readings: [FanReading] = []
    private(set) var readError: String?
    private(set) var installStatus: HelperInstallStatus
    private(set) var helperReachable = false
    private(set) var manualActive = false
    private(set) var statusMessage: String?
    /// Slider value per fan index, committed when the drag ends.
    var targets: [Int: Double] = [:]

    @ObservationIgnored let policy = FanSafetyPolicy()
    @ObservationIgnored private(set) var connectTask: Task<Void, Never>?
    @ObservationIgnored let source: FanReadingSource
    @ObservationIgnored let client: FanHelperClient
    @ObservationIgnored private let installer: FanHelperInstalling
    @ObservationIgnored private let heartbeat: HeartbeatScheduling
    @ObservationIgnored private let releaseGuard: ManualReleaseGuard
    @ObservationIgnored private let callbacks = PendingTasks()
    @ObservationIgnored private var started = false
    /// Bumped by every explicit way back to automatic ("Retour automatique", `stop()`). A
    /// `setTarget` reply from an earlier epoch is dropped: the user already overrode it, and
    /// since one XPC connection delivers messages in order the helper ran that automatic after
    /// the target, so it is automatic too.
    @ObservationIgnored var automaticEpoch = 0
    /// Set by the ported fan policy (`FanDriving`): told when manual mode ended without its own command.
    @ObservationIgnored var onManualEnded: (@MainActor (String?) -> Void)?

    init(source: FanReadingSource, client: FanHelperClient, installer: FanHelperInstalling,
         heartbeat: HeartbeatScheduling) {
        self.source = source
        self.client = client
        self.installer = installer
        self.heartbeat = heartbeat
        installStatus = installer.status
        releaseGuard = ManualReleaseGuard { [client] in client.sendAllAutomaticBlocking(timeout: 0.5) }
        client.onReachabilityChanged = { [weak self, callbacks] reachable in
            callbacks.add(Task { @MainActor [weak self] in self?.reachabilityChanged(reachable) })
        }
    }

    static func live() -> FansModel {
        FansModel(source: SMCFanReadingSource(), client: FanXPCClient(),
                  installer: SMAppServiceInstaller(), heartbeat: TaskHeartbeatScheduler())
    }

    var manualAvailable: Bool { installStatus == .enabled && helperReachable }

    /// Slider range of a fan: its SMC min and max when the policy trusts them.
    func range(for fan: Int) -> ClosedRange<Double>? {
        guard let r = readings.first(where: { $0.index == fan }), let lo = r.minRPM, let hi = r.maxRPM else { return nil }
        return policy.range(for: FanLimits(minRPM: lo, maxRPM: hi))
    }

    // MARK: - Lifecycle

    /// Idempotent. Connects to the helper only if it is already approved; never registers it.
    func start() {
        guard !started else { return }
        started = true
        connectTask = Task { [weak self] in await self?.connectIfEnabled() }
    }

    /// Idempotent. Sends automatic to a connected helper, stops the heartbeat, disconnects.
    func stop() {
        guard started else { return }
        started = false
        automaticEpoch += 1
        connectTask?.cancel()
        heartbeat.stop()
        if manualActive || helperReachable { client.sendAllAutomaticBlocking(timeout: 0.5) }
        endManual()
        client.disconnect()
        helperReachable = false
    }

    /// Called when the tab appears: picks up an approval given in System Settings meanwhile.
    func appeared() async {
        start()
        await connectTask?.value
        refreshInstallStatus()
        if installStatus == .enabled, !helperReachable { await connectIfEnabled() }
    }

    func connectIfEnabled() async {
        refreshInstallStatus()
        guard installStatus == .enabled else { return }
        let ok = await client.connect()
        guard started else { return }
        helperReachable = ok
        guard ok else {
            statusMessage = "Helper approuvé mais injoignable."
            return
        }
        // Manual mode this app instance did not set (an earlier instance died): end it now
        // rather than waiting for the helper's watchdog.
        if let state = try? await client.fetchState(), state.manualActive, !manualActive {
            _ = try? await client.perform(.allAutomatic)
        }
    }

    // MARK: - Monitoring

    func monitor() async {
        while !Task.isCancelled {
            await refreshReadings()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func refreshReadings() async {
        let source = self.source
        let result = await Task.detached(priority: .utility) { Result { try source.readFans() } }.value
        switch result {
        case .success(let fans):
            readings = fans
            readError = nil
            for fan in fans where targets[fan.index] == nil {
                if let start = fan.targetRPM ?? fan.minRPM { targets[fan.index] = start }
            }
        case .failure:
            readings = []
            readError = "Lecture des ventilateurs impossible (SMC)."
        }
    }

    // MARK: - Installation (explicit clicks only)

    func installHelper() {
        do {
            try installer.register()
            statusMessage = nil
        } catch {
            statusMessage = "Installation du helper impossible : \(error.localizedDescription)"
        }
        refreshInstallStatus()
        if installStatus == .requiresApproval {
            statusMessage = "Autorisez Mac Island dans Réglages Système > Général > Ouverture."
        }
        if installStatus == .enabled, started {
            connectTask = Task { [weak self] in await self?.connectIfEnabled() }
        }
    }

    func openLoginItems() { installer.openLoginItems() }

    func refreshInstallStatus() {
        installStatus = installer.status
        if installStatus != .enabled { helperReachable = false }
    }

    // MARK: - Manual control

    func commitTarget(fan: Int) async {
        guard manualAvailable, let range = range(for: fan), let wanted = targets[fan],
              let rpm = policy.clamp(wanted.rounded(), to: FanLimits(minRPM: range.lowerBound, maxRPM: range.upperBound))
        else { return }
        let epoch = automaticEpoch
        let result: FanCommandResult
        do {
            result = try await client.perform(.setTarget(fan: fan, rpm: rpm))
        } catch {
            if epoch == automaticEpoch { statusMessage = "Helper injoignable : commande non envoyée." }
            return
        }
        // "Retour automatique" or stop() went out while this request was in flight.
        guard epoch == automaticEpoch else { return }
        handle(result)
    }

    @discardableResult
    func returnToAutomatic() async -> FanDriverOutcome {
        automaticEpoch += 1
        heartbeat.stop()
        var outcome = FanDriverOutcome.unreachable
        do {
            let result = try await client.perform(.allAutomatic)
            outcome = Self.outcome(of: result)
            handle(result)
        } catch {
            statusMessage = "Helper injoignable : il repasse en automatique seul après 8 s sans signal."
        }
        endManual()
        return outcome
    }

    func sendHeartbeat() async {
        guard manualActive else {
            heartbeat.stop()
            return
        }
        if await !client.heartbeat() {
            endManual()
            statusMessage = "Le helper est repassé en automatique."
        }
    }

    /// Waits for connection callbacks already delivered (tests).
    func drainCallbacks() async {
        for task in callbacks.takeAll() { await task.value }
    }

    func handle(_ result: FanCommandResult) {
        switch result.status {
        case .applied:
            manualActive = true
            releaseGuard.manualActive = true
            if let fan = result.fan, let rpm = result.appliedRPM {
                targets[fan] = rpm
                statusMessage = "Ventilateur \(fan + 1) forcé à \(Int(rpm)) tr/min."
            }
            heartbeat.start(every: FanHelperContract.heartbeatInterval) { [weak self] in await self?.sendHeartbeat() }
        case .automatic:
            endManual()
            statusMessage = "Ventilateurs en mode automatique."
        case .forcedAutomatic:
            endManual()
            statusMessage = "Température élevée : retour automatique imposé par le helper."
        case .rejected:
            statusMessage = Self.rejectionMessage(result)
        case .failed:
            endManual()
            statusMessage = result.reason == "restorePending"
                ? "Le helper n'a pas pu remettre l'automatique : il réessaie chaque seconde."
                : "Écriture refusée par le SMC (\(result.reason ?? "inconnu")) : ventilateurs remis en automatique."
        }
    }

    private static func rejectionMessage(_ result: FanCommandResult) -> String {
        switch result.reason {
        case "rateLimited": "Trop rapide : réessayez dans un instant."
        case "unknownFan": "Ventilateur inconnu."
        case "invalidLimits": "Limites du ventilateur illisibles : contrôle manuel refusé."
        case "protocolVersion": "Version du helper différente : réinstallez l'app."
        default: "Commande refusée par le helper."
        }
    }

    private func reachabilityChanged(_ reachable: Bool) {
        if reachable {
            helperReachable = started && installStatus == .enabled
            return
        }
        helperReachable = false
        if manualActive {
            statusMessage = "Connexion au helper perdue : il repasse en automatique de lui-même."
        }
        endManual()
    }

    /// After a blocking automatic went out (`FanDriving.returnAllToAutomaticNow`): the local state follows.
    func stopManualAfterBlockingRestore() { endManual() }

    private func endManual() {
        let wasActive = manualActive
        manualActive = false
        releaseGuard.manualActive = false
        heartbeat.stop()
        if wasActive { onManualEnded?(statusMessage) }
    }
}

/// Tasks spawned from XPC callbacks (any thread), so tests can await them.
final class PendingTasks: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []

    func add(_ task: Task<Void, Never>) {
        lock.lock(); tasks.append(task); lock.unlock()
    }

    func takeAll() -> [Task<Void, Never>] {
        lock.lock(); defer { lock.unlock() }
        let all = tasks
        tasks.removeAll()
        return all
    }
}
