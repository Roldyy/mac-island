import AppKit
import ImageIO
import Observation

enum ClipboardSegment: String, CaseIterable, Identifiable {
    case history = "Historique"
    case scratchpad = "Bloc-notes"
    var id: String { rawValue }
}

/// State of the tab. Owns the store, the watcher, auto-clear and the plain-paste hotkey.
@MainActor
@Observable
final class ClipboardModel {
    var query = ""
    var segment: ClipboardSegment = .history
    private(set) var entries: [ClipboardEntry] = []
    private(set) var pads: [ScratchPad] = []
    private(set) var selectedPadID = ""
    private(set) var accessibilityTrusted = false
    private(set) var plainPasteStatus = ""
    /// "Disposition de l'historique": how the history pane draws its entries.
    private(set) var layout: ClipboardSettings.Layout = .list
    /// Empty when the history shortcut works or is off; otherwise why it does not.
    private(set) var historyShortcutStatus = ""

    @ObservationIgnored private let store: ClipboardHistoryStore
    @ObservationIgnored private let scratch: ScratchpadStore
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let settings: () -> ClipboardSettings
    @ObservationIgnored private let watcher: PasteboardWatcher
    @ObservationIgnored private let autoClear: AutoClearScheduler
    @ObservationIgnored private let accessibilityCheck: () -> Bool
    @ObservationIgnored private let postAccessCheck: () -> Bool
    @ObservationIgnored private let sendPaste: @MainActor () async -> PasteSendResult
    @ObservationIgnored private let notify: @MainActor (PlainPasteNotice) -> Void
    @ObservationIgnored private let hotkey: any PlainPasteHotkeyRegistering
    @ObservationIgnored private let historyHotkey: any PlainPasteHotkeyRegistering
    /// Lent by the app (this target cannot see the island): opens the island on the Presse-papiers tab.
    @ObservationIgnored private let openHistory: @MainActor () -> Void
    /// Where the menu bar preview text goes (nil: no preview). The app lends the menu bar item.
    @ObservationIgnored private let previewSink: @MainActor (String?) -> Void
    @ObservationIgnored private let workspaceCenter: NotificationCenter
    @ObservationIgnored private let distributedCenter: NotificationCenter
    @ObservationIgnored private var systemClear: SystemClearObserver?
    @ObservationIgnored private var lastPreview: String?
    @ObservationIgnored private var historyIntent: HistoryIntent?
    @ObservationIgnored private var applied: AppliedSettings?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false
    /// The files are read once, by the first start: a stop and a start never reload (and never drop) what is in memory.
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private let portedScratchpadRunning: @MainActor () -> Bool
    @ObservationIgnored private let stopCenter: NotificationCenter
    @ObservationIgnored private var stopObserver: NSObjectProtocol?
    @ObservationIgnored private var padSaveTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnails: [String: NSImage] = [:]

    init(dataDirectory: URL, pasteboard: NSPasteboard = .general,
         settings: @escaping () -> ClipboardSettings = { ClipboardSettings() },
         accessibilityTrusted: @escaping () -> Bool = { PlainPasteHotkeyService.accessibilityTrusted },
         postAccess: @escaping () -> Bool = { CGPreflightPostEventAccess() },
         sendPaste: @escaping @MainActor () async -> PasteSendResult = { await PasteKeySequencer.live().run() },
         notify: @escaping @MainActor (PlainPasteNotice) -> Void = { PlainPasteNotice.post($0) },
         hotkey: (any PlainPasteHotkeyRegistering)? = nil,
         historyHotkey: (any PlainPasteHotkeyRegistering)? = nil,
         openHistory: @escaping @MainActor () -> Void = { ClipboardFeature.openHistory() },
         previewSink: @escaping @MainActor (String?) -> Void = { ClipboardFeature.publishMenuBarPreview($0) },
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
         stopCenter: NotificationCenter = .default,
         portedScratchpadRunning: @escaping @MainActor () -> Bool = { ClipboardFeature.portedScratchpadRunning() }) {
        self.stopCenter = stopCenter
        self.portedScratchpadRunning = portedScratchpadRunning
        self.hotkey = hotkey ?? PlainPasteHotkeyService()
        // A model given its own plain-paste hotkey (tests) never takes a real key for the history either.
        self.historyHotkey = historyHotkey ?? (hotkey == nil ? HistoryHotkeyService() : UnregisteredHotkey())
        self.openHistory = openHistory
        self.previewSink = previewSink
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.accessibilityCheck = accessibilityTrusted
        self.accessibilityTrusted = accessibilityTrusted()
        self.postAccessCheck = postAccess
        self.sendPaste = sendPaste
        self.notify = notify
        self.pasteboard = pasteboard
        self.settings = settings
        store = ClipboardHistoryStore(directory: dataDirectory, limit: settings().historyLimit)
        scratch = ScratchpadStore(directory: dataDirectory)
        watcher = PasteboardWatcher(pasteboard: pasteboard)
        autoClear = AutoClearScheduler(pasteboard: pasteboard)
    }

    /// Idempotent for the data and the watcher; the hotkey is reconciled with the settings on EVERY call, so the
    /// registry restarting the feature (a permission grant, a switch back on) re-registers a hotkey that was
    /// dropped or whose shortcut changed meanwhile.
    func start() {
        hotkeyWanted = true
        guard !started else { reconcileHotkey(); reconcileHistoryHotkey(); return }
        started = true
        loadFilesIfNeeded()
        if stopObserver == nil {
            // The registry's stopper (kill switch, switch off, safe mode, quarantine) reaches this model by name.
            stopObserver = stopCenter.addObserver(forName: ClipboardFeature.stopRequested, object: nil,
                                                  queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }

        watcher.settings = settings
        watcher.onChange = { [weak self] count, capture, source in self?.handleChange(count, capture, source) }
        autoClear.didClear = { [weak self] in self?.watcher.syncToCurrent() }
        watcher.start()

        hotkey.onTrigger = { [weak self] in self?.plainPasteTriggered() }
        configureHotkey()
        historyHotkey.onTrigger = { [weak self] in self?.historyTriggered() }
        configureHistoryHotkey()
        applySettings(force: true)
        // The Settings page writes the switch and the shortcut to the defaults: follow them live.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    /// Every settings write lands here: the two hotkeys, then what the other rows change.
    func settingsChanged() {
        reconcileHotkey()
        reconcileHistoryHotkey()
        applySettings(force: false)
    }

    /// Reads the history and the scratchpad once, at the first start.
    private func loadFilesIfNeeded() {
        guard !loaded else { return }
        loaded = true
        store.load()
        scratch.load()
        // Retention at launch: what outlived its days while the app was closed goes now.
        store.purge(olderThanDays: settings().retentionDays)
        syncHistory()
        syncPads()
    }

    /// Looks at the pasteboard once, now (the watcher's own tick; tests drive it instead of waiting for the timer).
    func pollNow() { watcher.poll() }

    /// True while the pasteboard watcher runs (it is what records the history).
    var isMonitoring: Bool { watcher.isRunning }

    /// Ticks of the watcher's loop so far (tests wait on it before a negative assertion).
    var watcherPollCount: Int { watcher.pollCount }

    /// Stops monitoring: the watcher (nothing copied from now on is recorded), a pending auto-clear and the
    /// plain-paste hotkey. The history already recorded stays in memory and on disk. `start()` arms everything
    /// again; the watcher then takes the pasteboard as it is, so what was copied while stopped is never recorded.
    func stop() {
        hotkeyWanted = false
        hotkey.unregister()
        hotkeyRegistered = false
        historyHotkey.unregister()
        historyIntent = nil
        historyShortcutStatus = ""
        systemClear?.stop()
        applied = nil
        if lastPreview != nil { lastPreview = nil; previewSink(nil) }
        if started {
            started = false
            watcher.stop()
            autoClear.cancel()
            if let defaultsObserver {
                NotificationCenter.default.removeObserver(defaultsObserver)
                self.defaultsObserver = nil
            }
        }
        updatePlainPasteStatus()
    }

    // MARK: - Capture

    private func handleChange(_ count: Int, _ capture: PasteboardCapture?, _ source: String?) {
        let s = settings()
        store.limit = s.historyLimit
        switch capture {
        case .text(let t): store.addText(t, source: source)
        case .image(let png, let w, let h): store.addImage(png: png, width: w, height: h, source: source)
        case .files(let paths): store.addFiles(paths, source: source)
        case nil: break
        }
        // Retention on every copy, so a long-running session never keeps what is past its days.
        store.purge(olderThanDays: s.retentionDays)
        syncHistory()
        autoClear.schedule(delaySeconds: s.autoClearDelay, expectedChangeCount: count)
    }

    // MARK: - History actions

    var visibleEntries: [ClipboardEntry] { store.displayEntries(matching: query) }
    var unpinnedCount: Int { entries.filter { !$0.pinned }.count }

    func putBack(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        switch entry.kind {
        case .text:
            pasteboard.setString(entry.text, forType: .string)
        case .image:
            guard let url = store.imageURL(for: entry), let data = try? Data(contentsOf: url) else { return }
            pasteboard.setData(data, forType: .png)
        case .files:
            pasteboard.writeObjects(entry.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
        }
        watcher.syncToCurrent()
        store.moveToFront(id: entry.id)
        syncHistory()
        autoClear.schedule(delaySeconds: settings().autoClearDelay, expectedChangeCount: pasteboard.changeCount)
    }

    func togglePin(_ entry: ClipboardEntry) { store.togglePin(id: entry.id); syncHistory() }
    func remove(_ entry: ClipboardEntry) { thumbnails[entry.id] = nil; store.remove(id: entry.id); syncHistory() }
    func clearAll() { thumbnails.removeAll(); store.clearAll(keepPinned: true); syncHistory() }

    private func syncHistory() {
        entries = store.entries
        publishPreview()
    }

    // MARK: - Counts and actions of the Settings rows

    /// Read from the store, which reads its file on first ask: the Settings page shows the counts even while the
    /// feature is off and nothing started the model. No observed state changes here (a view reads it).
    var pinnedCount: Int { store.ensureLoaded(); return store.pinnedCount }
    var recentCount: Int { store.ensureLoaded(); return store.recentCount }

    /// "Effacer non épinglés" (the Settings button, after its own confirmation): the pinned items stay. The file is
    /// read first: a write on an unread store would replace the history with nothing.
    func clearUnpinned() { store.ensureLoaded(); clearAll() }

    /// Retention on demand (the island tab calls it when it opens).
    func purgeExpired() {
        if store.purge(olderThanDays: settings().retentionDays) { syncHistory() }
    }

    func thumbnail(for entry: ClipboardEntry) async -> NSImage? {
        if let cached = thumbnails[entry.id] { return cached }
        guard let url = store.imageURL(for: entry) else { return nil }
        let cg = await Task.detached(priority: .utility) { Self.makeThumbnail(url: url, maxPixel: 96) }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[entry.id] = image
        return image
    }

    nonisolated private static func makeThumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    // MARK: - History shortcut

    /// The shortcut opens the island on the Presse-papiers tab, history segment.
    func historyTriggered() {
        segment = .history
        openHistory()
    }

    private struct HistoryIntent: Equatable {
        /// What to register: nil when off or when the plain-paste key already holds the combination.
        var wanted: HotkeyShortcut?
        /// The switch (and the history) are on, whether or not the key can be registered.
        var switchedOn: Bool
    }

    private func intent(for s: ClipboardSettings) -> HistoryIntent {
        let on = s.historyEnabled && s.historyShortcutEnabled
        // The plain-paste key is registered first and keeps its combination.
        let clashes = s.pastePlainEnabled && s.pastePlainShortcut == s.historyShortcut
        return HistoryIntent(wanted: on && !clashes ? s.historyShortcut : nil, switchedOn: on)
    }

    private func configureHistoryHotkey() {
        let s = settings()
        let plan = intent(for: s)
        historyHotkey.unregister()
        historyIntent = plan
        if let wanted = plan.wanted {
            historyShortcutStatus = historyHotkey.register(wanted)
                ? "" : "Raccourci de l’historique : \(Self.display(wanted)) indisponible (déjà utilisé)"
        } else if plan.switchedOn {
            historyShortcutStatus = "Raccourci de l’historique : identique au collage sans style, qui le garde"
        } else {
            historyShortcutStatus = ""
        }
    }

    /// Registers, moves or releases the history key only when what is wanted changed: a key another app holds is
    /// tried once per change, not on every defaults write.
    private func reconcileHistoryHotkey() {
        guard hotkeyWanted, intent(for: settings()) != historyIntent else { return }
        configureHistoryHotkey()
    }

    // MARK: - Settings that change what is kept or shown

    /// What the settings rows (other than the two hotkeys) decide, compared as one value so a defaults write that
    /// changes none of them does nothing.
    private struct AppliedSettings: Equatable {
        var limit: Int
        var retentionDays: Int
        var layout: ClipboardSettings.Layout
        var previewOn: Bool
        var previewLength: Int
        var historyEnabled: Bool
        var clearOnSleep: Bool
        var clearOnDisplaySleep: Bool
        var clearOnLock: Bool

        init(_ s: ClipboardSettings) {
            limit = s.historyLimit
            retentionDays = s.retentionDays
            layout = s.layout
            previewOn = s.menuBarPreviewEnabled
            previewLength = s.menuBarPreviewLength
            historyEnabled = s.historyEnabled
            clearOnSleep = s.autoClearOnSleep
            clearOnDisplaySleep = s.autoClearOnDisplaySleep
            clearOnLock = s.autoClearOnScreenLock
        }
    }

    private func applySettings(force: Bool) {
        let s = settings()
        let now = AppliedSettings(s)
        guard force || now != applied else { return }
        let before = applied
        applied = now
        layout = s.layout
        if force || before?.limit != now.limit { store.limit = s.historyLimit }
        if force || before?.retentionDays != now.retentionDays {
            if store.purge(olderThanDays: s.retentionDays) { syncHistory() }
        }
        if systemClear == nil {
            systemClear = SystemClearObserver(workspaceCenter: workspaceCenter,
                                              distributedCenter: distributedCenter) { [weak self] in
                self?.clearSystemPasteboard()
            }
        }
        systemClear?.sync(sleep: s.autoClearOnSleep, displaySleep: s.autoClearOnDisplaySleep,
                          lock: s.autoClearOnScreenLock)
        publishPreview()
    }

    /// Sleep, display sleep or screen lock: the system pasteboard is emptied, the saved history stays.
    func clearSystemPasteboard() {
        pasteboard.clearContents()
        watcher.syncToCurrent()
        autoClear.cancel()
    }

    /// The menu bar preview: the newest recorded copy, cut to the chosen length. Sent only when it changed.
    private func publishPreview() {
        guard started else { return }
        let s = settings()
        let text = ClipboardPreview.menuBarText(newest: s.historyEnabled ? entries.first : nil,
                                                enabled: s.menuBarPreviewEnabled, length: s.menuBarPreviewLength)
        guard text != lastPreview else { return }
        lastPreview = text
        previewSink(text)
    }

    // MARK: - Plain paste

    func refreshAccessibility() {
        accessibilityTrusted = accessibilityCheck()
        updatePlainPasteStatus()
    }

    private func configureHotkey() {
        let s = settings()
        hotkey.unregister()
        hotkeyRegistered = s.pastePlainEnabled && hotkey.register(s.pastePlainShortcut)
        refreshAccessibility()
    }

    /// Registers, moves or releases the hotkey only when the settings no longer match what is registered.
    private func reconcileHotkey() {
        guard hotkeyWanted else { return }
        let s = settings()
        let wanted: HotkeyShortcut? = s.pastePlainEnabled ? s.pastePlainShortcut : nil
        guard hotkey.registered != wanted else { return }
        configureHotkey()
    }

    @ObservationIgnored private var hotkeyRegistered = false
    /// False between `stop()` and the next `start()`: settings changes must not re-arm a released hotkey.
    @ObservationIgnored private var hotkeyWanted = false

    @discardableResult
    func plainPasteTriggered() -> PlainPasteOutcome {
        PasteLog.logger.notice("hotkey fired")
        refreshAccessibility()
        let notify = self.notify
        let outcome = PlainPasteHotkeyService.performPlainPaste(
            pasteboard: pasteboard, accessibilityTrusted: accessibilityCheck, postAccess: postAccessCheck,
            sendPaste: sendPaste,
            didSend: { if $0 == .eventFailed { notify(.eventFailed) } }
        ) { [watcher, autoClear, pasteboard, settings] in
            // The rewrite is ours: do not record it back, and re-arm auto-clear on the NEW count
            // so the old timer (bound to the previous count) cannot fire on, or be skipped for, it.
            watcher.syncToCurrent()
            autoClear.schedule(delaySeconds: settings().autoClearDelay, expectedChangeCount: pasteboard.changeCount)
        }
        // Never silent: the plain text is on the pasteboard in every case but "nothing to paste".
        switch outcome {
        case .pasted: break
        case .copiedOnly: notify(.needsPermission)
        case .nothingToPaste: notify(.nothingToPaste)
        }
        return outcome
    }

    private func updatePlainPasteStatus() {
        let s = settings()
        let label = Self.display(s.pastePlainShortcut)
        if !s.pastePlainEnabled {
            plainPasteStatus = "Collage sans style désactivé"
        } else if !hotkeyRegistered {
            plainPasteStatus = "Collage sans style : \(label) indisponible (déjà utilisé)"
        } else if !accessibilityTrusted {
            plainPasteStatus = "Collage sans style : autorisation Accessibilité requise"
        } else {
            plainPasteStatus = "Collage sans style actif : \(label)"
        }
    }

    static func display(_ s: HotkeyShortcut) -> String {
        var out = ""
        if s.modifiers.contains(.control) { out += "⌃" }
        if s.modifiers.contains(.option) { out += "⌥" }
        if s.modifiers.contains(.shift) { out += "⇧" }
        if s.modifiers.contains(.command) { out += "⌘" }
        return out + s.key.uppercased()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Scratchpad

    /// True while the ported Scratchpad owns `Scratchpad.json`: this pane is then read-only (it would keep a stale
    /// copy and rewrite the whole file over the ported edits).
    var scratchpadReadOnly: Bool { portedScratchpadRunning() }

    var padText: String {
        get { pads.first { $0.id == selectedPadID }?.text ?? "" }
        set {
            guard !scratchpadReadOnly else { return }
            scratch.updateText(newValue, for: selectedPadID)
            syncPads()
            scheduleScratchSave()
        }
    }

    func selectPad(_ id: String) { scratch.select(id); syncPads() }
    func addPad() {
        guard !scratchpadReadOnly else { return }
        scratch.addPad(named: "Note \(pads.count + 1)"); syncPads(); saveScratch()
    }
    func removeSelectedPad() {
        guard !scratchpadReadOnly else { return }
        scratch.removePad(id: selectedPadID); syncPads(); saveScratch()
    }

    /// Re-reads the file (what the ported Scratchpad wrote) into the pane. A no-op while nothing changed.
    func reloadScratchpadIfChanged() {
        guard scratch.changedOnDisk else { return }
        scratch.load()
        syncPads()
    }

    private func syncPads() { pads = scratch.pads; selectedPadID = scratch.selectedID }

    /// Saves, unless the file changed under us: then the file wins (it holds the ported edits) and the pane reloads.
    func saveScratch() {
        guard !scratchpadReadOnly else { return }
        if !scratch.save() { reloadScratchpadIfChanged() }
    }

    private func scheduleScratchSave() {
        padSaveTask?.cancel()
        padSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveScratch()
        }
    }
}
