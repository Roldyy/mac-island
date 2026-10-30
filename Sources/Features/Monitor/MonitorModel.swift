import Foundation
import Observation

/// Samples CPU, memory and thermal state, feeds the gauges and the alert engine.
///
/// Cost model: 1 Hz while the tab is visible, the migrated 5-10 s cadence only while alerts are
/// enabled, nothing otherwise. Processes are listed only while visible. Nothing is logged.
@MainActor @Observable
final class MonitorModel {
    static let topCount = 5

    // MARK: Observed state
    private(set) var cpuPercent: Double?
    private(set) var memoryPercent: Double?
    private(set) var pressure: MemoryPressure = .unknown
    private(set) var thermal: ThermalLevel = .nominal
    private(set) var cpuHistory = SampleHistory()
    private(set) var memoryHistory = SampleHistory()
    private(set) var topByCPU: [ProcessUsage] = []
    private(set) var topByMemory: [ProcessUsage] = []
    private(set) var notificationStatus: NotificationAuthorization = .notDetermined
    private(set) var activeInterval: TimeInterval?
    private(set) var loopGeneration = 0
    private(set) var isVisible = false
    private var activeAlerts: [AlertMetric: AlertNotice] = [:]

    /// The latest alert still active (and not dismissed): what the shell shows in the wings.
    var currentAlert: AlertNotice? { activeAlerts.values.max { $0.raisedAt < $1.raisedAt } }

    // MARK: Settings, written through on change
    var alertsEnabled: Bool {
        didSet {
            guard alertsEnabled != oldValue else { return }
            settings.setAlertsEnabled(alertsEnabled)
            if !alertsEnabled {
                evaluator.reset()
                activeAlerts.removeAll()
            }
            reschedule()
        }
    }
    var cpuThreshold: Double { didSet { if cpuThreshold != oldValue { settings.setCPUThreshold(cpuThreshold) } } }
    var memoryThreshold: Double {
        didSet { if memoryThreshold != oldValue { settings.setMemoryThreshold(memoryThreshold) } }
    }
    var sustainedSeconds: Int {
        didSet { if sustainedSeconds != oldValue { settings.setSustainedSeconds(sustainedSeconds) } }
    }
    var cooldownMinutes: Int {
        didSet { if cooldownMinutes != oldValue { settings.setCooldownMinutes(cooldownMinutes) } }
    }
    var systemNotificationsEnabled: Bool {
        didSet {
            if systemNotificationsEnabled != oldValue {
                settings.setSystemNotificationsEnabled(systemNotificationsEnabled)
            }
        }
    }

    // MARK: Dependencies and private state
    @ObservationIgnored private let settings: MonitorSettings
    @ObservationIgnored private let cpu: CPUSampling
    @ObservationIgnored private let memory: MemorySampling
    @ObservationIgnored private let thermalSampler: ThermalSampling
    @ObservationIgnored private let processes: ProcessSampling
    @ObservationIgnored private let notifier: NotificationDelivering
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let uptimeNs: () -> UInt64
    @ObservationIgnored private var evaluator = AlertEvaluator()
    @ObservationIgnored private var tracker = ProcessCPUTracker()
    @ObservationIgnored private var previousTicks: [CPUTicks]?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(settings: MonitorSettings = MonitorSettings(),
         cpu: CPUSampling = MachCPUSampler(),
         memory: MemorySampling = MachMemorySampler(),
         thermal: ThermalSampling = ProcessThermalSampler(),
         processes: ProcessSampling = MachProcessSampler(),
         notifier: NotificationDelivering = SystemNotificationCenter(),
         clock: @escaping () -> Date = Date.init,
         uptimeNs: @escaping () -> UInt64 = { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }) {
        self.settings = settings
        self.cpu = cpu
        self.memory = memory
        self.thermalSampler = thermal
        self.processes = processes
        self.notifier = notifier
        self.clock = clock
        self.uptimeNs = uptimeNs
        alertsEnabled = settings.alertsEnabled
        cpuThreshold = settings.cpuThreshold
        memoryThreshold = settings.memoryThreshold
        sustainedSeconds = settings.sustainedSeconds
        cooldownMinutes = settings.cooldownMinutes
        systemNotificationsEnabled = settings.systemNotificationsEnabled
    }

    // MARK: Lifecycle

    /// Idempotent.
    func start() {
        guard !started else { return }
        started = true
        reschedule()
        // Read-only (never prompts): without it a relaunch forgets the permission the user already gave.
        Task { [weak self] in await self?.refreshNotificationStatus() }
    }

    /// Idempotent.
    func stop() {
        guard started else { return }
        started = false
        reschedule()
    }

    /// Called by the view: the tab is on screen (1 Hz, processes) or not.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        tracker.reset()
        if !visible {
            topByCPU = []
            topByMemory = []
        }
        reschedule()
    }

    private var cadence: TimeInterval? {
        guard started else { return nil }
        return SamplingCadence.interval(visible: isVisible, alertsEnabled: alertsEnabled,
                                        background: TimeInterval(settings.intervalSeconds))
    }

    private func reschedule() {
        let wanted = cadence
        if wanted == activeInterval, (wanted == nil) == (loop == nil) { return }
        loop?.cancel()
        loop = nil
        activeInterval = wanted
        guard let interval = wanted else {
            // Nothing runs: the next sample must not diff against an hours-old reading.
            previousTicks = nil
            return
        }
        loopGeneration += 1
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .seconds(interval), tolerance: .milliseconds(100))
            }
        }
    }

    // MARK: Sampling

    func tick() {
        if let ticks = cpu.ticks() {
            if let previous = previousTicks,
               let usage = UsageMath.cpuUsage(previous: previous, current: ticks) {
                cpuPercent = usage
                cpuHistory.append(usage)
            }
            previousTicks = ticks
        }
        if let counts = memory.read() {
            let used = UsageMath.memoryUsedPercent(counts)
            memoryPercent = used
            memoryHistory.append(used)
        } else {
            memoryPercent = nil
        }
        pressure = memory.pressure()
        thermal = thermalSampler.level()
        if isVisible { sampleProcesses() }
        if alertsEnabled { evaluateAlerts() }
    }

    private func sampleProcesses() {
        let stats = tracker.update(processes.snapshot(), nowNs: uptimeNs())
        topByCPU = ProcessRanking.topByCPU(stats, limit: Self.topCount).map(usage)
        topByMemory = ProcessRanking.topByMemory(stats, limit: Self.topCount).map(usage)
    }

    private func usage(_ stat: ProcessStat) -> ProcessUsage {
        ProcessUsage(pid: stat.pid, name: processes.name(pid: stat.pid),
                     cpuPercent: stat.cpuPercent, residentBytes: stat.residentBytes)
    }

    // MARK: Alerts

    private func rule(_ threshold: Double) -> AlertRule {
        settings.rule(threshold: threshold, sustainedSeconds: sustainedSeconds, cooldownMinutes: cooldownMinutes)
    }

    private func evaluateAlerts() {
        let now = clock()
        if let value = cpuPercent, let event = evaluator.evaluate(.cpu, value: value, rule: rule(cpuThreshold), now: now) {
            handle(event, now: now)
        }
        if let value = memoryPercent,
           let event = evaluator.evaluate(.memory, value: value, rule: rule(memoryThreshold), now: now) {
            handle(event, now: now)
        }
    }

    private func handle(_ event: AlertEvent, now: Date) {
        switch event {
        case .raised(let metric, let value):
            let notice = AlertNotice(metric: metric, value: value, raisedAt: now)
            activeAlerts[metric] = notice
            if notificationMode == .system { notifier.post(title: notice.title, body: notice.message) }
        case .cleared(let metric):
            activeAlerts[metric] = nil
        }
    }

    /// Hide the notice. The evaluator stays active, so it does not come back until the signal
    /// has fallen and risen again.
    func dismissCurrentAlert() {
        guard let current = currentAlert else { return }
        activeAlerts[current.metric] = nil
    }

    // MARK: System notifications

    var hasBundle: Bool { notifier.hasBundle }

    var notificationMode: NotificationPolicy.Mode {
        NotificationPolicy.mode(hasBundle: notifier.hasBundle, status: notificationStatus,
                                userEnabled: systemNotificationsEnabled)
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notifier.authorizationStatus()
    }

    /// From the visible "Autoriser" button only; never at launch.
    func requestNotificationAuthorization() async {
        guard notifier.hasBundle else { return }
        let granted = await notifier.requestAuthorization()
        notificationStatus = await notifier.authorizationStatus()
        if granted { systemNotificationsEnabled = true }
    }
}
