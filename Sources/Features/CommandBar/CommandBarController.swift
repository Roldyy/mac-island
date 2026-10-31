import Observation

@MainActor
protocol CommandBarPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func hide()
}

/// Owns the hotkey lifecycle and the settings the tab edits. `start()` / `stop()` are idempotent.
@MainActor
@Observable
final class CommandBarController {
    private(set) var status: HotkeyStatus = .off
    var enabled: Bool
    var habitsEnabled: Bool
    var sources: [String: Bool]
    var hotkeyDraft: String
    private(set) var hotkeyInvalid = false

    @ObservationIgnored private let settings: CommandBarSettings
    @ObservationIgnored private let registrar: HotkeyRegistering
    @ObservationIgnored private let presenter: CommandBarPresenting
    @ObservationIgnored private let habits: HabitStore
    @ObservationIgnored private var started = false

    init(settings: CommandBarSettings, registrar: HotkeyRegistering, presenter: CommandBarPresenting,
         habits: HabitStore) {
        self.settings = settings
        self.registrar = registrar
        self.presenter = presenter
        self.habits = habits
        self.enabled = settings.enabled
        self.habitsEnabled = settings.habitsEnabled
        self.sources = Dictionary(uniqueKeysWithValues: CommandBarSettings.sourceIDs.map { ($0, settings.sourceEnabled($0)) })
        self.hotkeyDraft = settings.hotkey.stored
    }

    var hotkeyDisplay: String { settings.hotkey.display }

    func start() {
        guard !started else { return }
        guard settings.enabled else { status = .off; return }
        let spec = settings.hotkey
        let code = registrar.register(spec) { [weak self] in self?.toggle() }
        status = .from(osStatus: code, spec: spec)
        // A conflict leaves nothing registered, so a later start() may try again.
        started = (code == 0)
    }

    func stop() {
        if presenter.isVisible { presenter.hide() }
        if started { registrar.unregister() }
        started = false
        status = .off
    }

    /// Opens the bar from a button (not the hotkey); a bar already open stays open.
    func show() {
        if !presenter.isVisible { presenter.show() }
    }

    func toggle() {
        if presenter.isVisible { presenter.hide() } else { presenter.show() }
    }

    private func restart() {
        stop()
        start()
    }

    /// Validates, stores in canonical form and re-registers. False when the text is not a shortcut.
    @discardableResult
    func applyHotkey(_ raw: String) -> Bool {
        guard let spec = HotkeySpec.parse(raw) else { hotkeyInvalid = true; return false }
        hotkeyInvalid = false
        settings.hotkeyRaw = spec.stored
        hotkeyDraft = spec.stored
        restart()
        return true
    }

    func enabledChanged() {
        settings.enabled = enabled
        applyEnabled()
    }

    /// Settings are the source of truth: re-read, then start or stop.
    func applyEnabled() {
        enabled = settings.enabled
        if enabled { start() } else { stop() }
    }

    func habitsChanged() {
        settings.habitsEnabled = habitsEnabled
        applyHabits()
    }

    /// Switching habits off also wipes them, memory and file.
    func applyHabits() {
        habitsEnabled = settings.habitsEnabled
        if !habitsEnabled { habits.clear() }
    }

    func clearHabits() { habits.clear() }

    func sourceChanged(_ id: String) {
        settings.setSource(id, enabled: sources[id] ?? true)
    }
}
