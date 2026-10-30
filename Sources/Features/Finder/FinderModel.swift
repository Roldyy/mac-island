import AppKit
import Observation

/// State of the tab. Owns the controller and the key tap; `start()` / `stop()` are idempotent.
@MainActor
@Observable
final class FinderModel {
    var cutPasteEnabled: Bool { didSet { settings.cutPasteEnabled = cutPasteEnabled; refresh() } }
    var pasteImageAsFile: Bool { didSet { settings.pasteImageAsFile = pasteImageAsFile; refresh() } }
    private(set) var accessibility = false
    private(set) var inputMonitoring = false
    private(set) var automation: AutomationStatus = .unknown
    private(set) var tapRunning = false
    private(set) var cutCount = 0
    private(set) var outcome: FinderOutcome?
    private(set) var needsConfirmation = false

    @ObservationIgnored private let settings: FinderSettings
    @ObservationIgnored private let controller: FinderController
    @ObservationIgnored private var tap: KeyEventTap?
    @ObservationIgnored private var started = false

    init(settings: FinderSettings = FinderSettings(), controller: FinderController? = nil) {
        self.settings = settings
        cutPasteEnabled = settings.cutPasteEnabled
        pasteImageAsFile = settings.pasteImageAsFile
        self.controller = controller ?? FinderController(
            scripting: AppleScriptFinder(), environment: SystemFinderEnvironment(), pasteboard: SystemPasteboard(),
            settings: { (settings.cutPasteEnabled, settings.pasteImageAsFile) })
        self.controller.onChange = { [weak self] in self?.syncFromController() }
    }

    var permissionLine: String {
        FinderStatusText.permissions(accessibility: accessibility, inputMonitoring: inputMonitoring,
                                     tapRunning: tapRunning, enabled: cutPasteEnabled || pasteImageAsFile)
    }
    var automationLine: String { FinderStatusText.automation(automation) }
    var outcomeLine: String { FinderStatusText.outcome(outcome) }
    var cutLine: String { cutCount == 0 ? "Rien de coupé" : "Coupé : \(cutCount)" }

    func start() {
        guard !started else { return }
        started = true
        refresh()
    }

    func stop() {
        guard started else { return }
        started = false
        tap?.stop()
        tap = nil
        tapRunning = false
        controller.cancelCut()
    }

    /// Re-reads permissions and cut state, and (re)installs the tap when it should run.
    /// Cheap; the tab calls it while visible. Never prompts.
    func refresh() {
        accessibility = KeyEventTap.accessibilityTrusted
        inputMonitoring = KeyEventTap.inputMonitoringGranted
        let wanted = started && (cutPasteEnabled || pasteImageAsFile)
        if wanted {
            if tap == nil {
                let t = KeyEventTap { [weak self] chord in self?.controller.handleKey(chord) ?? false }
                t.onLost = { [weak self] in self?.refresh() }
                tap = t
            }
            tapRunning = tap?.start() ?? false
        } else {
            tap?.stop()
            tap = nil
            tapRunning = false
        }
        syncFromController()
        Task.detached {
            let s = AutomationPermission.status(ask: false)
            await MainActor.run { self.automation = s }
        }
    }

    /// From a visible button only: shows the system Automation prompt for Finder.
    func requestAutomation() {
        Task.detached {
            let s = AutomationPermission.status(ask: true)
            await MainActor.run { self.automation = s }
        }
    }

    func openAccessibilitySettings() { open("Privacy_Accessibility") }
    func openInputMonitoringSettings() { open("Privacy_ListenEvent") }
    func cancelCut() { controller.cancelCut() }
    func confirmLargeMove() { controller.confirmLargeMove() }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func syncFromController() {
        cutCount = controller.cutCount
        outcome = controller.outcome
        needsConfirmation = controller.awaitingConfirmation != nil
    }
}
