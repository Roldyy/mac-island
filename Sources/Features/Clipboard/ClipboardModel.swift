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

    @ObservationIgnored private let store: ClipboardHistoryStore
    @ObservationIgnored private let scratch: ScratchpadStore
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let settings: () -> ClipboardSettings
    @ObservationIgnored private let watcher: PasteboardWatcher
    @ObservationIgnored private let autoClear: AutoClearScheduler
    @ObservationIgnored private let accessibilityCheck: () -> Bool
    @ObservationIgnored private let sendPaste: () -> Void
    @ObservationIgnored private let hotkey = PlainPasteHotkeyService()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var padSaveTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnails: [String: NSImage] = [:]

    init(dataDirectory: URL, pasteboard: NSPasteboard = .general,
         settings: @escaping () -> ClipboardSettings = { ClipboardSettings() },
         accessibilityTrusted: @escaping () -> Bool = { PlainPasteHotkeyService.accessibilityTrusted },
         sendPaste: @escaping () -> Void = { PlainPasteHotkeyService.postCommandV() }) {
        self.accessibilityCheck = accessibilityTrusted
        self.accessibilityTrusted = accessibilityTrusted()
        self.sendPaste = sendPaste
        self.pasteboard = pasteboard
        self.settings = settings
        store = ClipboardHistoryStore(directory: dataDirectory, limit: settings().historyLimit)
        scratch = ScratchpadStore(directory: dataDirectory)
        watcher = PasteboardWatcher(pasteboard: pasteboard)
        autoClear = AutoClearScheduler(pasteboard: pasteboard)
    }

    /// Idempotent: loads data, starts the watcher and registers the hotkey once.
    func start() {
        guard !started else { return }
        started = true
        store.load()
        scratch.load()
        syncHistory()
        syncPads()

        watcher.settings = settings
        watcher.onChange = { [weak self] count, capture, source in self?.handleChange(count, capture, source) }
        autoClear.didClear = { [weak self] in self?.watcher.syncToCurrent() }
        watcher.start()

        hotkey.onTrigger = { [weak self] in self?.plainPasteTriggered() }
        configureHotkey()
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

    private func syncHistory() { entries = store.entries }

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

    // MARK: - Plain paste

    func refreshAccessibility() {
        accessibilityTrusted = accessibilityCheck()
        updatePlainPasteStatus()
    }

    private func configureHotkey() {
        let s = settings()
        hotkey.unregister()
        if s.pastePlainEnabled { hotkeyRegistered = hotkey.register(s.pastePlainShortcut) }
        refreshAccessibility()
    }

    @ObservationIgnored private var hotkeyRegistered = false

    @discardableResult
    func plainPasteTriggered() -> PlainPasteOutcome {
        refreshAccessibility()
        return PlainPasteHotkeyService.performPlainPaste(
            pasteboard: pasteboard, accessibilityTrusted: accessibilityCheck, sendPaste: sendPaste
        ) { [watcher, autoClear, pasteboard, settings] in
            // The rewrite is ours: do not record it back, and re-arm auto-clear on the NEW count
            // so the old timer (bound to the previous count) cannot fire on, or be skipped for, it.
            watcher.syncToCurrent()
            autoClear.schedule(delaySeconds: settings().autoClearDelay, expectedChangeCount: pasteboard.changeCount)
        }
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

    var padText: String {
        get { pads.first { $0.id == selectedPadID }?.text ?? "" }
        set {
            scratch.updateText(newValue, for: selectedPadID)
            syncPads()
            scheduleScratchSave()
        }
    }

    func selectPad(_ id: String) { scratch.select(id); syncPads() }
    func addPad() { scratch.addPad(named: "Note \(pads.count + 1)"); syncPads(); scratch.save() }
    func removeSelectedPad() { scratch.removePad(id: selectedPadID); syncPads(); scratch.save() }

    private func syncPads() { pads = scratch.pads; selectedPadID = scratch.selectedID }

    private func scheduleScratchSave() {
        padSaveTask?.cancel()
        padSaveTask = Task { [scratch] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            scratch.save()
        }
    }
}
