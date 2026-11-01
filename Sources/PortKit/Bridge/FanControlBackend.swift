// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W6C (fans, UI and policy). The lane owns this file.

import AppKit
import FansFeature
import Foundation

/// Reads the temperatures through upstream's own SMC reader. Read-only: nothing here writes, and nothing outside
/// `FanControlHardware.swift` calls its write methods (a source test pins that).
final class FanControlProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var hardware: FanControlHardware?

    func temperatures() -> [FanControlTemperatureReading] {
        lock.lock(); defer { lock.unlock() }
        if hardware == nil { hardware = FanControlHardware() }
        return hardware?.readTemperatures() ?? []
    }
}

/// The ported fan policy over Mac Island's helper.
///
/// `FanControlService` (upstream's observable the ported card reads) is a shim over this class. Everything that
/// can move a fan goes through one `FanDriving` driver, the Fans model, which owns the XPC client, the heartbeat
/// and the helper's watchdog. Rules this class keeps, in order of importance:
///
/// - **Journal first.** `fanControlRecoveryNeeded` is set BEFORE the first speed is sent and cleared only when the
///   helper answered "automatic". A crash, a kill or a quit that could not confirm leaves it set, and the next
///   launch (`recoverAtLaunch`) hands the fans back before any feature starts.
/// - **Automatic on every way out.** Stop (switch, kill switch, safe mode, crash quarantine), quit, sleep, a
///   thermal state of serious or critical, the user's temperature ceiling, a refused heartbeat, a lost connection,
///   a sensor missing three ticks in a row and any refused or failed write all end in automatic mode.
/// - **Never prompt, never register.** Only `authorize()` (a click) registers the helper or opens System Settings.
@MainActor
final class FanControlBackend {
    static let shared = FanControlBackend()

    struct State: Equatable {
        var accessState: FanControlService.AccessState = .notRegistered
        var snapshot: FanControlSnapshot = .empty
        var error: FanControlErrorCode?
        var isWorking = false
        /// True from the registry's start to its stop: the settings page is live only then.
        var isRunning = false
    }

    struct Environment {
        var driver: @MainActor () -> any FanDriving
        var temperatures: @Sendable () -> [FanControlTemperatureReading]
        var thermalState: @Sendable () -> ProcessInfo.ThermalState
        var defaults: @MainActor () -> UserDefaults
        var tickInterval: TimeInterval
        /// False in tests: nothing schedules a tick behind the test's back.
        var schedulesTicks = true

        @MainActor static var live: Environment {
            let probe = FanControlProbe()
            return Environment(
                driver: { FansFeature.driver },
                temperatures: { probe.temperatures() },
                thermalState: { ProcessInfo.processInfo.thermalState },
                defaults: { PortHost.defaults },
                tickInterval: 2)
        }
    }

    private(set) var state = State()
    var onChange: ((State) -> Void)?

    private let environment: Environment
    private var cachedDriver: (any FanDriving)?
    private var started = false
    private var panelVisible = false
    private var loop: Task<Void, Never>?
    private var loopGeneration = 0
    /// Bumped when control starts or ends: a tick that read before the change drops its decision.
    private var controlGeneration = 0
    private var tickInFlight = false
    private var tickCount = 0
    private var activeConfiguration: FanControlConfiguration?
    private var appliedLevel: Int?
    private var appliedTargets: [Int: Double] = [:]
    private var temperatureFailures = 0
    private var lastStopReason: FanControlStopReason?
    private var stickyError: FanControlErrorCode?
    private var isReturning = false
    private var isSending = false
    /// The last apply or resume started from a click or a wake, for tests to await.
    private(set) var pendingApply: Task<Void, Never>?
    private var observersInstalled = false

    init(environment: Environment? = nil) {
        self.environment = environment ?? .live
    }

    var isControlling: Bool { activeConfiguration != nil }
    private var defaults: UserDefaults { environment.defaults() }
    private var journalIsSet: Bool { defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) }

    private var driver: any FanDriving {
        if let cachedDriver { return cachedDriver }
        let made = environment.driver()
        made.onManualEnded = { [weak self] _ in self?.driverEndedManual() }
        cachedDriver = made
        return made
    }

    // MARK: - Lifecycle (the registry's start and stop)

    /// Idempotent. Arms nothing that moves a fan: control starts only from a click, or from a resume the person
    /// asked for (`fanControlResume`).
    func start() {
        guard !started else { return }
        started = true
        state.isRunning = true
        publish()
        if let configuration = resumableConfiguration, driver.access == .enabled {
            pendingApply = Task { await applyConfigurationNow(configuration) }
        } else {
            requestTick()
        }
    }

    /// The registry stopped the feature (switch, kill switch, safe mode, quarantine) or the app quits: every fan back
    /// to automatic, now.
    func stop() {
        started = false
        state.isRunning = false
        panelVisible = false
        handBackNow(reason: nil)
        cancelLoop()
        publish()
    }

    /// Quit: the same hand-back, synchronous, waits at most half a second. The journal stays set because a blocking
    /// send cannot confirm; the next launch finds it and hands back again, which is harmless.
    func stopNow() {
        guard isControlling || journalIsSet || (cachedDriver?.isManualActive ?? false) else { return }
        handBackNow(reason: nil)
    }

    private func handBackNow(reason: FanControlStopReason?) {
        let mustSend = isControlling || journalIsSet || (cachedDriver?.isManualActive ?? false)
        controlGeneration += 1
        activeConfiguration = nil
        appliedLevel = nil
        appliedTargets = [:]
        temperatureFailures = 0
        lastStopReason = reason
        if mustSend {
            isReturning = true
            driver.returnAllToAutomaticNow()
            isReturning = false
        }
    }

    // MARK: - Launch recovery

    /// Hands back what an earlier run left forced. Entered only when the journal is set (`PortBridge.recoverAtLaunch`),
    /// before any feature starts. Never resumes (a resume waits for the registry to start the feature) and never
    /// registers or prompts: without an approved helper the fans stay with the system and the journal stays.
    func recoverAtLaunch() {
        guard journalIsSet, !isControlling else { return }
        Task { await recoverAutomatic() }
    }

    func recoverAutomatic() async {
        let driver = self.driver
        driver.refreshAccess()
        guard driver.access == .enabled else { return }
        await driver.connectIfApproved()
        guard driver.isReachable else { return }
        isReturning = true
        let outcome = await driver.returnAllToAutomatic()
        isReturning = false
        if outcome == .automatic { defaults.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded) }
        requestTick()
    }

    // MARK: - What the settings page and the card call

    func panelDidAppear() {
        panelVisible = true
        requestTick()
        ensureLoop()
    }

    func panelDidDisappear() {
        panelVisible = false
    }

    func refresh() { requestTick() }

    /// A click on "Autoriser" / "Ouvrir les Réglages": the only path that registers the helper or opens System
    /// Settings.
    func authorize() {
        let driver = self.driver
        driver.refreshAccess()
        switch driver.access {
        case .requiresApproval:
            driver.openApprovalSettings()
        case .enabled:
            requestTick()
        case .notFound:
            stickyError = .helperUnavailable
        case .notRegistered:
            driver.installHelper()
            driver.refreshAccess()
            if driver.access == .requiresApproval { driver.openApprovalSettings() }
            if driver.access == .notFound { stickyError = .helperUnavailable }
        }
        requestTick()
        publish()
    }

    func applyConfiguration(_ configuration: FanControlConfiguration) {
        // Only while the registry runs the feature: a switch that is off, the kill switch and safe mode all stop it.
        guard started else { return }
        guard FanControlPolicy.validConfiguration(configuration) else {
            stickyError = .controlFailed
            publish()
            return
        }
        if configuration.mode == .system {
            returnToSystem()
            return
        }
        guard driver.access == .enabled else {
            authorize()
            return
        }
        pendingApply = Task { await applyConfigurationNow(configuration) }
    }

    /// The person's own way back: forgets the resume and hands the fans to macOS.
    func returnToSystem() {
        defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        restoreAutomatic()
    }

    func restoreAutomatic() {
        pendingApply = Task { await restoreNow(reason: nil) }
    }

    func resumePreferenceDidChange() {
        guard defaults.bool(forKey: DefaultsKey.fanControlResume) else {
            defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            return
        }
        if let configuration = activeConfiguration {
            rememberForResume(configuration)
        } else {
            defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        }
    }

    // MARK: - Applying a configuration

    /// Journal first, then one read, then the first speeds. Any refusal ends in automatic.
    func applyConfigurationNow(_ configuration: FanControlConfiguration) async {
        guard started, FanControlPolicy.validConfiguration(configuration), configuration.mode != .system else { return }
        let driver = self.driver
        state.isWorking = true
        stickyError = nil
        publish()
        defer { state.isWorking = false; publish() }

        driver.refreshAccess()
        guard driver.access == .enabled else { return }
        defaults.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)  // journal first
        if !driver.isReachable { await driver.connectIfApproved() }
        guard driver.isReachable else {
            stickyError = .helperUnavailable
            await restoreNow(reason: nil, keepError: true)
            return
        }
        guard let fans = await driver.readFans(), !fans.isEmpty else {
            stickyError = .controlFailed
            await restoreNow(reason: nil, keepError: true)
            return
        }
        controlGeneration += 1
        activeConfiguration = configuration
        appliedLevel = nil
        appliedTargets = [:]
        temperatureFailures = 0
        lastStopReason = nil
        let result = FanControlEngine.evaluate(input(configuration: configuration, fans: Self.readings(fans),
                                                     temperatures: await readTemperatures()))
        temperatureFailures = result.temperatureFailures
        switch result.step {
        case .apply(let level, let targets):
            if await send(level: level, targets: targets) {
                rememberForResume(configuration)
                ensureLoop()
            }
        case .hold:
            // A curve whose sensor does not exist here: refuse at once rather than wait three ticks.
            stickyError = .controlFailed
            await restoreNow(reason: .temperatureUnavailable, keepError: true)
        case .restore(let reason):
            stickyError = .controlFailed
            await restoreNow(reason: reason, keepError: true)
        }
    }

    // MARK: - Ticks

    private func requestTick() {
        guard environment.schedulesTicks else { return }
        Task { await tick() }
    }

    /// Reads fans and temperatures, publishes the snapshot, and, while a configuration is active, evaluates the
    /// safety rules and the curve and sends what changed.
    func tick() async {
        guard !tickInFlight, !state.isWorking else { return }
        tickInFlight = true
        defer { tickInFlight = false }
        tickCount += 1
        let driver = self.driver
        driver.refreshAccess()
        // Read-only until the registry started the feature: a switched-off feature never opens the helper connection.
        if started, driver.access == .enabled, !driver.isReachable, tickCount.isMultiple(of: 5) || !isControlling {
            await driver.connectIfApproved()
        }
        let generation = controlGeneration
        let fans = await driver.readFans()
        let temperatures = await readTemperatures()
        guard !Task.isCancelled else { return }
        publishSnapshot(fans: fans, temperatures: temperatures)
        guard generation == controlGeneration, let configuration = activeConfiguration else { return }

        // A reading that fails while control is active is not "everything is fine": three misses and macOS takes over.
        guard let fans else {
            temperatureFailures += 1
            if temperatureFailures >= FanControlPolicy.temperatureFailureLimit {
                await restoreNow(reason: .hardwareChanged)
            }
            return
        }
        if fans.isEmpty {
            await restoreNow(reason: .hardwareChanged)
            return
        }
        let result = FanControlEngine.evaluate(input(configuration: configuration, fans: Self.readings(fans),
                                                     temperatures: temperatures))
        temperatureFailures = result.temperatureFailures
        switch result.step {
        case .hold: break
        case .apply(let level, let targets): _ = await send(level: level, targets: targets)
        case .restore(let reason): await restoreNow(reason: reason)
        }
    }

    private func input(configuration: FanControlConfiguration, fans: [FanControlFanReading],
                       temperatures: [FanControlTemperatureReading]) -> FanControlEngine.Input {
        let stored = defaults.object(forKey: FanControlEngine.ceilingKey) as? Double
        return FanControlEngine.Input(
            configuration: configuration, temperatures: temperatures, fans: fans, appliedLevel: appliedLevel,
            appliedTargets: appliedTargets, thermalState: environment.thermalState(),
            ceilingCelsius: stored ?? FanControlEngine.defaultCeiling, temperatureFailures: temperatureFailures)
    }

    private func readTemperatures() async -> [FanControlTemperatureReading] {
        let read = environment.temperatures
        return await Task.detached(priority: .utility) { read() }.value
    }

    // MARK: - Sending

    /// Sends the speeds, fan by fan. True when every fan took its speed. A rate-limit refusal is retried next tick;
    /// every other refusal, a failed write or no answer ends in automatic.
    @discardableResult
    private func send(level: Int, targets: [Int: Double]) async -> Bool {
        let driver = self.driver
        let generation = controlGeneration
        isSending = true
        defer { isSending = false }
        for (fan, rpm) in targets.sorted(by: { $0.key < $1.key }) {
            let outcome = await driver.setTarget(fan: fan, rpm: rpm)
            guard generation == controlGeneration, activeConfiguration != nil else { return false }
            switch outcome {
            case .applied:
                appliedTargets[fan] = rpm
            case .rejected(let reason) where reason == "rateLimited":
                return false
            case .automatic, .forcedAutomatic:
                // The helper took the fans back itself (it is too hot, or an explicit return won the race).
                finishControl(reason: .thermalPressure, confirmedAutomatic: true)
                return false
            case .rejected, .failed:
                stickyError = .controlFailed
                await restoreNow(reason: .hardwareChanged, keepError: true)
                return false
            case .unreachable:
                stickyError = .helperUnavailable
                await restoreNow(reason: .appDisconnected, keepError: true)
                return false
            }
        }
        appliedLevel = level
        publish()
        return true
    }

    // MARK: - Ending control

    /// Hands every fan back and, when the helper confirms, closes the journal.
    func restoreNow(reason: FanControlStopReason?, keepError: Bool = false) async {
        controlGeneration += 1
        let hadControl = isControlling || journalIsSet
        activeConfiguration = nil
        appliedLevel = nil
        appliedTargets = [:]
        temperatureFailures = 0
        lastStopReason = reason
        if !keepError { stickyError = nil }
        guard hadControl || (cachedDriver?.isManualActive ?? false) else { publish(); return }
        let driver = self.driver
        state.isWorking = true
        publish()
        isReturning = true
        let outcome = await driver.returnAllToAutomatic()
        isReturning = false
        state.isWorking = false
        switch outcome {
        case .automatic:
            defaults.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
        case .unreachable, .failed:
            // The helper's watchdog (8 s without a heartbeat) and its disconnect handler restore on their own.
            if stickyError == nil { stickyError = .helperUnavailable }
        default:
            break
        }
        requestTick()
        publish()
    }

    /// Control ended without a command of ours (the helper took the fans back). The journal closes only when the
    /// helper itself answered "automatic"; after a lost heartbeat or connection it stays, and the next launch
    /// hands back again (harmless).
    private func finishControl(reason: FanControlStopReason, confirmedAutomatic: Bool) {
        controlGeneration += 1
        activeConfiguration = nil
        appliedLevel = nil
        appliedTargets = [:]
        temperatureFailures = 0
        lastStopReason = reason
        if confirmedAutomatic { defaults.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded) }
        publish()
    }

    private func driverEndedManual() {
        // During our own command the outcome carries the reason; here it is the helper's watchdog or the connection.
        guard !isReturning, !isSending, isControlling else { return }
        finishControl(reason: .heartbeatLost, confirmedAutomatic: false)
    }

    // MARK: - Resume

    private var resumableConfiguration: FanControlConfiguration? {
        guard defaults.bool(forKey: DefaultsKey.fanControlResume),
              defaults.string(forKey: DefaultsKey.fanControlMode) != FanControlMode.system.rawValue else { return nil }
        return FanControlConfiguration.decodeResume(
            defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) ?? "")
    }

    private func rememberForResume(_ configuration: FanControlConfiguration) {
        guard defaults.bool(forKey: DefaultsKey.fanControlResume),
              let stored = FanControlConfiguration.encodeResume(configuration) else { return }
        defaults.set(stored, forKey: DefaultsKey.fanControlResumeConfiguration)
    }

    // MARK: - Sleep, wake and quit (the live app only)

    /// Sleep hands the fans back, wake resumes only when the person asked for it, quit hands back synchronously.
    func installSystemObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopNow() }
        }
    }

    func willSleep() {
        guard isControlling || journalIsSet else { return }
        handBackNow(reason: nil)
        publish()
    }

    func didWake() {
        guard started else { return }
        if let configuration = resumableConfiguration, driver.access == .enabled {
            pendingApply = Task { await applyConfigurationNow(configuration) }
        } else if journalIsSet {
            recoverAtLaunch()
        } else {
            requestTick()
        }
    }

    // MARK: - Snapshot

    private func ensureLoop() {
        guard loop == nil, panelVisible || isControlling else { return }
        loopGeneration += 1
        let generation = loopGeneration
        let interval = environment.tickInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.panelVisible || self.isControlling else { break }
                await self.tick()
                try? await Task.sleep(for: .seconds(interval))
            }
            self?.loopEnded(generation)
        }
    }

    private func loopEnded(_ generation: Int) {
        if generation == loopGeneration { loop = nil }
    }

    private func cancelLoop() {
        loop?.cancel()
        loop = nil
        loopGeneration += 1
    }

    private static func readings(_ fans: [FanDriverFan]) -> [FanControlFanReading] {
        fans.map {
            FanControlFanReading(index: $0.index, actualRPM: $0.actualRPM ?? 0, minimumRPM: $0.minRPM ?? 0,
                                 maximumRPM: $0.maxRPM ?? 0, targetRPM: $0.targetRPM ?? 0,
                                 isManuallyControlled: $0.isManual)
        }
    }

    private static func access(_ driverAccess: FanDriverAccess) -> FanControlService.AccessState {
        switch driverAccess {
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .enabled: .enabled
        case .notFound: .unavailable
        }
    }

    private func publishSnapshot(fans: [FanDriverFan]?, temperatures: [FanControlTemperatureReading]) {
        let driver = self.driver
        var next = state
        next.accessState = Self.access(driver.access)
        let readings = Self.readings(fans ?? [])
        next.snapshot = FanControlSnapshot(
            fans: readings, isCooling: isControlling, endsAt: nil, stopReason: lastStopReason,
            coolingLevel: isControlling ? appliedLevel : nil, configuration: activeConfiguration,
            temperatures: temperatures.isEmpty ? nil : temperatures)
        if let stickyError {
            next.error = stickyError
        } else if fans == nil {
            next.error = .unsupportedHardware
        } else if readings.isEmpty {
            next.error = .noFans
        } else if next.accessState == .enabled, !driver.isReachable {
            next.error = .helperUnavailable
        } else if !isControlling, readings.contains(where: \.isManuallyControlled) {
            next.error = .alreadyControlled
        } else {
            next.error = nil
        }
        state = next
        onChange?(state)
    }

    private func publish() {
        var next = state
        if let cachedDriver { next.accessState = Self.access(cachedDriver.access) }
        next.snapshot.isCooling = isControlling
        next.snapshot.configuration = activeConfiguration
        next.snapshot.coolingLevel = isControlling ? appliedLevel : nil
        next.snapshot.stopReason = lastStopReason
        if let stickyError { next.error = stickyError }
        else if next.error == .controlFailed || next.error == .helperUnavailable { next.error = nil }
        state = next
        onChange?(state)
    }
}
