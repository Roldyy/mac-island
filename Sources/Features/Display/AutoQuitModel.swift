import Foundation
import Observation
import os

/// Drives the auto-quit scan loop and holds what the tab shows. Settings write through at once.
@MainActor @Observable
final class AutoQuitModel {
    static let scanInterval: TimeInterval = 15
    private static let log = Logger(subsystem: "be.roldy.macisland", category: "autoquit")

    var enabled: Bool {
        didSet {
            settings.autoQuitEnabled = enabled
            if !enabled { engine.reset(); pending = [] }
        }
    }
    var dryRun: Bool { didSet { settings.autoQuitDryRun = dryRun } }
    var delayMinutes: Int {
        didSet {
            let clamped = min(DisplaySettings.maxDelayMinutes, max(1, delayMinutes))
            if clamped != delayMinutes { delayMinutes = clamped; return }
            settings.autoQuitDelayMinutes = clamped
        }
    }
    private(set) var exclusions: [String]
    private(set) var pending: [PendingQuit] = []
    /// Dock apps that could be added to the exclusion list.
    private(set) var candidatesToExclude: [AppSnapshot] = []

    @ObservationIgnored private var settings: DisplaySettings
    @ObservationIgnored private var engine = AutoQuitEngine()
    @ObservationIgnored private let scanner: RunningAppScanning
    @ObservationIgnored private let terminator: AppTerminating
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let ownPID: Int32
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(settings: DisplaySettings = DisplaySettings(),
         scanner: RunningAppScanning = RunningAppScanner(),
         terminator: AppTerminating = WorkspaceTerminator(),
         clock: @escaping () -> Date = Date.init,
         ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
         sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
         }) {
        self.settings = settings
        self.scanner = scanner
        self.terminator = terminator
        self.clock = clock
        self.ownPID = ownPID
        self.sleep = sleep
        enabled = settings.autoQuitEnabled
        dryRun = settings.autoQuitDryRun
        delayMinutes = settings.autoQuitDelayMinutes
        exclusions = settings.autoQuitExcludedBundleIDs.sorted()
    }

    var isRunning: Bool { loop != nil }

    /// Idempotent: a second call while running does nothing.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                await self.sleep(Self.scanInterval)
            }
        }
    }

    /// Idempotent. Stopping forgets the idle clocks: the next start waits a full interval again.
    func stop() {
        loop?.cancel()
        loop = nil
        engine.reset()
        pending = []
    }

    func tick() {
        let apps = scanner.snapshot()
        candidatesToExclude = apps.filter { $0.isRegular && $0.bundleID != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let config = AutoQuitConfig(delay: TimeInterval(delayMinutes) * 60,
                                    userExclusions: Set(exclusions), ownPID: ownPID)
        let output = engine.tick(apps: apps, now: clock(), config: config, enabled: enabled, dryRun: dryRun)
        pending = output.pending
        var quit = 0
        for pid in output.terminate where terminator.terminate(pid: pid) { quit += 1 }
        if !output.pending.isEmpty || !output.terminate.isEmpty {
            Self.log.info("scan: \(apps.count) apps, \(output.pending.count) announced, \(output.terminate.count) asked to quit, \(quit) accepted")
        }
    }

    func addExclusion(_ bundleID: String) {
        guard !bundleID.isEmpty, !exclusions.contains(bundleID) else { return }
        exclusions = (exclusions + [bundleID]).sorted()
        settings.autoQuitExcludedBundleIDs = Set(exclusions)
        pending.removeAll { $0.bundleID == bundleID }
    }

    func removeExclusion(_ bundleID: String) {
        exclusions.removeAll { $0 == bundleID }
        settings.autoQuitExcludedBundleIDs = Set(exclusions)
    }
}
