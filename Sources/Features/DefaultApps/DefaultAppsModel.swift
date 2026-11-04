import AppKit
import Foundation
import Observation

/// State and intents of the "Applications par défaut" panel, shared by the island tab and the Settings page.
///
/// Nothing is written until the user has seen a preview and clicked "Appliquer": `buildPreview()` only computes,
/// `confirmAndApply()` is the one door to a write and refuses without a preview on screen.
@MainActor @Observable
public final class DefaultAppsModel {
    public enum Phase: Equatable { case idle, scanning, ready }
    public enum Mode: Equatable { case all, pick }
    public enum Pending: Equatable { case undoLast, restoreAll }

    public private(set) var isActive = false
    public private(set) var phase: Phase = .idle
    public private(set) var scan: ScanResult = .empty
    /// Replacement candidates for the selected source, computed off the main thread when the source or the scan changes.
    public private(set) var candidates: [ReplacementCandidate] = []

    // Replace flow
    public private(set) var selectedSourceID: String?
    public private(set) var selectedReplacementID: String?
    public private(set) var mode: Mode = .all
    public private(set) var pickedTypes: Set<String> = []
    public private(set) var explicitProtected: Set<String> = []

    // Scheme flow
    public private(set) var schemeAppID: String?
    public private(set) var scheme: String?
    public private(set) var schemeConfirmedProtected = false

    // Preview and result
    public private(set) var preview: ReplacementPreview?
    public private(set) var report: ApplyReport?
    public private(set) var isApplying = false
    public private(set) var pending: Pending?

    public private(set) var journalEntries: [JournalEntry] = []
    public private(set) var journalNotice: String?
    public private(set) var recentLog: [String] = []

    public let settings: DefaultAppsSettings

    @ObservationIgnored private var confirmedPreviewID: UUID?
    @ObservationIgnored private let environment: DefaultAppsEnvironment
    @ObservationIgnored let scanner: DefaultAppsScanner
    @ObservationIgnored let planner: ReplacementPlanner
    @ObservationIgnored let journal: DefaultAppsJournalStore
    @ObservationIgnored let choices: DefaultAppsChoicesStore
    @ObservationIgnored let applier: DefaultAppsApplier
    @ObservationIgnored let keeper: DefaultAppsGuard
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var scanTask: Task<ScanResult, Never>?
    @ObservationIgnored private var guardTask: Task<Void, Never>?
    @ObservationIgnored private var candidatesTask: Task<Void, Never>?
    /// What the applier and the guard ask before every write (they are built before `self` exists).
    @ObservationIgnored private let activity = Activity()
    @ObservationIgnored let gate = DefaultAppsWriteGate()

    public init(environment: DefaultAppsEnvironment) {
        self.environment = environment
        settings = DefaultAppsSettings(defaults: environment.defaults)
        scanner = DefaultAppsScanner(launchServices: environment.launchServices, catalog: environment.catalog)
        planner = ReplacementPlanner(catalog: environment.catalog)
        journal = DefaultAppsJournalStore(defaults: environment.defaults)
        choices = DefaultAppsChoicesStore(defaults: environment.defaults)
        // The log sink needs `self`, so the collaborators are built with a forwarding closure.
        let sink = LogSink()
        let activity = activity
        let gate = gate
        applier = DefaultAppsApplier(launchServices: environment.launchServices, planner: planner, journal: journal,
                                     choices: choices, now: environment.now, log: { sink.write($0) },
                                     gate: gate, shouldContinue: { activity.active })
        keeper = DefaultAppsGuard(settings: settings, choices: choices, launchServices: environment.launchServices,
                                  now: environment.now, log: { sink.write($0) },
                                  gate: gate, allowed: { activity.active && !activity.applying })
        sink.target = { [weak self] line in self?.appendLog(line) }
        sink.forward = environment.log
    }

    // MARK: lifecycle

    /// Allows the feature. Reads the journal (a local value), runs the guard once when it is on. Nothing is scanned
    /// or written here.
    public func start() {
        guard !isActive else { return }
        isActive = true
        activity.active = true
        reloadJournal()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.guardCheck(reason: "activation") }
        }
        guardCheck(reason: "launch")
    }

    /// Switch off, kill switch, safe mode: forgets everything on screen. The journal and the choices stay in defaults.
    public func stop() {
        isActive = false
        activity.active = false
        scanTask?.cancel()
        scanTask = nil
        guardTask?.cancel()
        guardTask = nil
        candidatesTask?.cancel()
        candidatesTask = nil
        candidates = []
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        phase = .idle
        scan = .empty
        resetFlow()
        report = nil
        pending = nil
    }

    // MARK: scan

    /// Reads the installed apps and their current defaults, off the main actor.
    public func refresh() async {
        guard isActive, phase != .scanning else { return }
        phase = .scanning
        let scanner = scanner
        let task = Task { await Task.detached(priority: .userInitiated) { scanner.scan() }.value }
        scanTask = task
        let result = await task.value
        guard isActive, !task.isCancelled else { return }
        scanTask = nil
        scan = result
        phase = .ready
        if let id = selectedSourceID, scan.replaceable.first(where: { $0.id == id }) == nil { resetFlow() }
        updateCandidates()
        reloadJournal()
    }

    public var replaceable: [ReplaceableApp] { scan.replaceable }

    public var source: ReplaceableApp? { selectedSourceID.flatMap { id in scan.replaceable.first { $0.id == id } } }

    public var replacement: AppProfile? { selectedReplacementID.flatMap(scan.app) }

    /// Waits for the candidate list of the current source (the tests, and nothing else, need this).
    public func settleCandidates() async { await candidatesTask?.value }

    private func updateCandidates() {
        candidatesTask?.cancel()
        candidatesTask = nil
        candidates = []
        guard isActive, let source else { return }
        let planner = planner
        let apps = scan.apps
        candidatesTask = Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) { planner.candidates(for: source, among: apps) }.value
            guard !Task.isCancelled, let self, self.isActive, self.selectedSourceID == source.id else { return }
            self.candidates = list
        }
    }

    // MARK: replace flow

    public func selectSource(_ id: String?) {
        guard id != selectedSourceID else { return }
        resetFlow()
        selectedSourceID = id
        report = nil
        updateCandidates()
    }

    public func selectReplacement(_ id: String?) {
        selectedReplacementID = id
        invalidatePreview()
    }

    public func setMode(_ mode: Mode) {
        self.mode = mode
        invalidatePreview()
    }

    public func togglePicked(_ typeID: String) {
        if pickedTypes.contains(typeID) { pickedTypes.remove(typeID); explicitProtected.remove(typeID) } else { pickedTypes.insert(typeID) }
        invalidatePreview()
    }

    /// A protected type is changed only when it is both ticked and confirmed here.
    public func setProtectedConfirmed(_ typeID: String, _ on: Bool) {
        if on { explicitProtected.insert(typeID); pickedTypes.insert(typeID) } else { explicitProtected.remove(typeID) }
        invalidatePreview()
    }

    /// Computes what would change. Writes nothing.
    public func buildPreview() {
        guard isActive, let source, let replacement else { return }
        let selection: TypeSelection = mode == .all ? .all : .picked(pickedTypes)
        preview = planner.preview(source: source, replacement: replacement, selection: selection,
                                  explicitProtected: explicitProtected, scan: scan)
        confirmedPreviewID = nil
        report = nil
    }

    // MARK: scheme flow

    public var schemeApps: [AppProfile] { scan.apps.filter { !$0.declared.schemes.isEmpty }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    public func selectSchemeApp(_ id: String?) {
        schemeAppID = id
        scheme = nil
        schemeConfirmedProtected = false
        invalidatePreview()
    }

    public func selectScheme(_ scheme: String?) {
        self.scheme = scheme
        schemeConfirmedProtected = false
        invalidatePreview()
    }

    public func setSchemeConfirmed(_ on: Bool) {
        schemeConfirmedProtected = on
        invalidatePreview()
    }

    public func buildSchemePreview() {
        guard isActive, let id = schemeAppID, let app = scan.app(id), let scheme else { return }
        let current = environment.launchServices.defaultHandlerBundleID(forScheme: scheme)
        preview = planner.schemePreview(replacement: app, scheme: scheme, confirmedProtected: schemeConfirmedProtected,
                                        currentHandler: current, currentName: scan.name(of: current))
        confirmedPreviewID = nil
        report = nil
    }

    // MARK: apply

    public func cancelPreview() { invalidatePreview() }
    public func dismissReport() { report = nil }

    /// The one door to a write. Needs the preview on screen; the click that calls this is the confirmation.
    public func confirmAndApply() async {
        guard isActive, !isApplying, let preview, !preview.items.isEmpty else { return }
        confirmedPreviewID = preview.id
        setApplying(true)
        let result = await applier.apply(preview, confirmedPreviewID: confirmedPreviewID)
        setApplying(false)
        // Switched off while it ran (kill switch): nothing more is shown or re-read.
        guard isActive else { return }
        report = result
        self.preview = nil
        confirmedPreviewID = nil
        reloadJournal()
        await rescanQuietly()
    }

    // MARK: undo

    public func requestUndoLast() { if !journalEntries.isEmpty { pending = .undoLast } }
    public func requestRestoreAll() { if !journalEntries.isEmpty { pending = .restoreAll } }
    public func cancelPending() { pending = nil }

    /// Runs the undo the user just confirmed (the second click).
    public func confirmPending() async {
        guard isActive, !isApplying, let action = pending else { return }
        pending = nil
        let entries = journal.entries
        let targets: [JournalEntry]
        switch action {
        case .undoLast: targets = entries.last.map { [$0] } ?? []
        case .restoreAll: targets = entries
        }
        guard !targets.isEmpty else { return }
        setApplying(true)
        let result = await applier.undo(entries: targets, restoringOriginals: action == .restoreAll)
        setApplying(false)
        guard isActive else { return }
        report = result
        preview = nil
        reloadJournal()
        await rescanQuietly()
    }

    // MARK: guard

    public func setGuard(_ on: Bool) {
        settings.guardEnabled = on
        if on { guardCheck(reason: "réglage") }
    }

    func guardCheck(reason: String) {
        // Never during an apply or an undo (they own the writes), never once the feature is off.
        guard isActive, !isApplying, settings.guardEnabled else { return }
        guardTask = Task { [keeper] in await keeper.check(reason: reason) }
    }

    private func setApplying(_ on: Bool) {
        isApplying = on
        activity.applying = on
    }

    // MARK: helpers

    public var lastEntry: JournalEntry? { journalEntries.last }
    public var storedChoiceCount: Int { choices.choices.count }

    func reloadJournal() {
        switch journal.load() {
        case .journal(let stored):
            journalEntries = stored.entries
            journalNotice = nil
        case .unsupportedVersion:
            journalEntries = []
            journalNotice = "Le journal vient d’une version plus récente de l’app : aucun changement n’est possible tant qu’il n’est pas lisible."
        case .corrupt:
            journalEntries = []
            journalNotice = "Le journal était illisible : une copie est gardée, un journal vide sera utilisé."
        }
    }

    private func invalidatePreview() {
        preview = nil
        confirmedPreviewID = nil
    }

    private func resetFlow() {
        candidatesTask?.cancel()
        candidatesTask = nil
        candidates = []
        selectedSourceID = nil
        selectedReplacementID = nil
        mode = .all
        pickedTypes = []
        explicitProtected = []
        schemeAppID = nil
        scheme = nil
        schemeConfirmedProtected = false
        invalidatePreview()
    }

    /// Re-reads the defaults after a write, keeping the user's place and the result on screen.
    private func rescanQuietly() async {
        let keep = report
        let source = selectedSourceID
        phase = .idle
        await refresh()
        report = keep
        if let source, scan.replaceable.contains(where: { $0.id == source }) { selectedSourceID = source; updateCandidates() }
    }

    private func appendLog(_ line: String) {
        recentLog.append(line)
        if recentLog.count > 8 { recentLog.removeFirst(recentLog.count - 8) }
    }

    /// The two flags the collaborators read before each write. Main actor only, like the loops that read them.
    @MainActor private final class Activity {
        var active = false
        var applying = false
    }

    /// Lets collaborators built before `self` exists write to the model and the system log.
    private final class LogSink: @unchecked Sendable {
        var target: (@MainActor @Sendable (String) -> Void)?
        var forward: (@Sendable (String) -> Void)?

        func write(_ line: String) {
            forward?(line)
            let target = target
            Task { @MainActor in target?(line) }
        }
    }
}
