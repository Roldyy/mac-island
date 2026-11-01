// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W4B (recorder). The lane owns this file.

import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import CoreMedia
import IslandKit
import SwiftUI

// MARK: - Safety policy (pure)

/// Where the screen recorder may run and when it must stop by itself. Pure: every input is a value.
///
/// A recording can never run unnoticed. While one runs there are three visible signs (the red item in the closed
/// island, the menu bar item, the floating pill of the upstream recorder), one shortcut that stops it from any app,
/// and these automatic stops, each of which saves what was recorded instead of throwing it away.
enum RecorderSafetyPolicy {
    /// Under this much free space the recording stops (the upstream service stops at 500 MB; this is stricter).
    static let minimumFreeBytes: Int64 = 1_000_000_000
    /// The longest recording a person can allow, in minutes. There is no "unlimited".
    static let allowedMaxMinutes = [5, 15, 30, 60, 120]
    static let defaultMaxMinutes = 60
    /// A recording left paused this long is stopped: a paused stream still holds the screen.
    static let maximumPauseSeconds = 30 * 60
    /// The free space is read this often, in seconds of recording (the read is slow, never on the main thread).
    static let diskCheckEverySeconds = 5

    enum StopReason: Equatable {
        case maxDuration, lowDisk, pausedTooLong, displaySleep, screenLocked

        /// What the person reads once the file is saved (French, the HUD of the upstream recorder shows it).
        var message: String {
            switch self {
            case .maxDuration: "Enregistrement arrêté : durée maximale atteinte. La vidéo est enregistrée."
            case .lowDisk: "Enregistrement arrêté : moins de 1 Go d’espace libre. La vidéo est enregistrée."
            case .pausedTooLong: "Enregistrement arrêté : en pause depuis trop longtemps. La vidéo est enregistrée."
            case .displaySleep: "Enregistrement arrêté : l’écran s’est mis en veille. La vidéo est enregistrée."
            case .screenLocked: "Enregistrement arrêté : la session s’est verrouillée. La vidéo est enregistrée."
            }
        }
    }

    /// A stored value, clamped to the allowed list: nothing or a non-positive value is the default, anything
    /// between two choices goes to the next one up, anything past the last is the last.
    static func sanitizedMaxMinutes(_ raw: Int) -> Int {
        guard raw > 0 else { return defaultMaxMinutes }
        return allowedMaxMinutes.first { $0 >= raw } ?? allowedMaxMinutes[allowedMaxMinutes.count - 1]
    }

    /// The reason to stop now, nil to go on. `freeBytes` is nil when no reading came back yet (no reason to stop).
    static func stopReason(elapsedSeconds: Int, maxMinutes: Int, freeBytes: Int64?, pausedSeconds: Int) -> StopReason? {
        if let freeBytes, freeBytes < minimumFreeBytes { return .lowDisk }
        if pausedSeconds >= maximumPauseSeconds { return .pausedTooLong }
        if elapsedSeconds >= sanitizedMaxMinutes(maxMinutes) * 60 { return .maxDuration }
        return nil
    }

    /// The item of the closed island: alert priority, a red dot, the elapsed time.
    static func islandActivity(elapsedSeconds: Int, paused: Bool) -> IslandActivity {
        let label = RecorderSupport.elapsedLabel(seconds: elapsedSeconds)
        return IslandActivity(
            id: RecorderLane.activityID, source: RecorderLane.source, priority: .alert,
            leading: CompactItem(symbol: paused ? "pause.circle.fill" : "record.circle.fill",
                                 text: paused ? "Enregistrement en pause \(label)" : "Enregistrement \(label)",
                                 status: paused ? .warning : .danger),
            showsDot: true)
    }
}

/// The two settings of the safety section, in the host's defaults. Hand-written keys, nothing upstream reads them.
enum RecorderSafetyKeys {
    static let maxMinutes = "macisland.recorder.maxMinutes"
    static let stopOnSleepOrLock = "macisland.recorder.stopOnSleepOrLock"

    static func maxMinutes(in defaults: UserDefaults) -> Int {
        RecorderSafetyPolicy.sanitizedMaxMinutes((defaults.object(forKey: maxMinutes) as? Int) ?? 0)
    }

    /// On unless the person turned it off.
    static func stopsOnSleepOrLock(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: stopOnSleepOrLock) as? Bool) ?? true
    }
}

// MARK: - Seams (live implementations below, fakes in the tests)

/// What the lane reads and asks of the upstream recorder.
struct RecorderState: Equatable {
    var isRecording = false
    var isPaused = false
    var elapsedSeconds = 0
}

@MainActor
protocol RecorderControlling: AnyObject {
    var state: RecorderState { get }
    /// Calls `handler` with every new state; the returned closure stops the observation.
    func observe(_ handler: @escaping @MainActor (RecorderState) -> Void) -> () -> Void
    /// Stops the recording and saves the file (a `reason` goes straight to the folder, with that message).
    func stop(reason: String?)
    func togglePause()
    /// The upstream `syncWithPreferences`: sweeps leftovers when the feature is on, ends the recording and closes
    /// its editors when the registry turned it off.
    func syncWithPreferences()
}

struct RecorderIslandPoster {
    var post: @MainActor (IslandActivity, Duration?) -> Void
    var withdraw: @MainActor (String) -> Void

    static let live = RecorderIslandPoster(
        post: { ActivityCenter.shared.post($0, expiresAfter: $1) },
        withdraw: { ActivityCenter.shared.withdraw(id: $0) })
}

struct RecorderStatusActions {
    var stop: @MainActor () -> Void
    var togglePause: @MainActor () -> Void
}

@MainActor
protocol RecorderStatusPresenting: AnyObject {
    func show(elapsed: String, paused: Bool, actions: RecorderStatusActions)
    func hide()
}

/// The global stop shortcut. Registered only while a recording runs.
@MainActor
protocol RecorderStopHotkeying: AnyObject {
    @discardableResult func register(onPress: @escaping @MainActor () -> Void) -> Bool
    func unregister()
}

enum RecorderSystemEvent: Equatable { case displaySleep, screenLocked }

@MainActor
protocol RecorderSystemEventSource: AnyObject {
    func observe(_ handler: @escaping @MainActor (RecorderSystemEvent) -> Void) -> () -> Void
}

// MARK: - The supervisor

/// Watches the recorder and keeps the signs of a recording visible; ends it when it must end.
///
/// `arm()` starts watching, `disarm()` stops (and takes every sign down). Nothing runs before `arm`, and nothing is
/// left after `disarm`: no observer, no hotkey, no menu bar item, no island item.
@MainActor
final class RecorderSafety {
    struct Dependencies {
        var island: RecorderIslandPoster
        var statusItem: RecorderStatusPresenting
        var hotkey: RecorderStopHotkeying
        var events: RecorderSystemEventSource
        /// Free space where the recordings are written, nil when it cannot be read. Off the main thread.
        var freeBytes: @Sendable () async -> Int64?
        var now: () -> Date
        var defaults: () -> UserDefaults
    }

    private let control: RecorderControlling
    private let deps: Dependencies
    private var stopObservation: (() -> Void)?
    private var stopEvents: (() -> Void)?
    private var recordingShown = false
    private var stopRequested = false
    private var pausedSince: Date?
    private var lastFreeBytes: Int64?
    private var generation = 0

    private(set) var isArmed = false

    init(control: RecorderControlling, dependencies: Dependencies) {
        self.control = control
        self.deps = dependencies
    }

    func arm() {
        guard !isArmed else { return }
        isArmed = true
        stopObservation = control.observe { [weak self] state in self?.update(state) }
        stopEvents = deps.events.observe { [weak self] event in self?.handle(event) }
        update(control.state)
    }

    func disarm() {
        stopObservation?()
        stopEvents?()
        stopObservation = nil
        stopEvents = nil
        isArmed = false
        takeSignsDown()
    }

    /// One reading of the recorder. Idempotent: the same state twice changes nothing.
    func update(_ state: RecorderState) {
        guard isArmed else { return }
        guard state.isRecording else {
            takeSignsDown()
            return
        }
        if !recordingShown {
            recordingShown = true
            stopRequested = false
            lastFreeBytes = nil
            generation += 1
            deps.hotkey.register { [weak self] in self?.control.stop(reason: nil) }
        }
        if state.isPaused {
            if pausedSince == nil { pausedSince = deps.now() }
        } else {
            pausedSince = nil
        }
        deps.island.post(RecorderSafetyPolicy.islandActivity(elapsedSeconds: state.elapsedSeconds, paused: state.isPaused),
                         nil)
        deps.statusItem.show(elapsed: RecorderSupport.elapsedLabel(seconds: state.elapsedSeconds), paused: state.isPaused,
                             actions: RecorderStatusActions(
                                 stop: { [weak self] in self?.control.stop(reason: nil) },
                                 togglePause: { [weak self] in self?.control.togglePause() }))
        evaluate(state)
        if state.elapsedSeconds % RecorderSafetyPolicy.diskCheckEverySeconds == 0 {
            let token = generation
            Task { @MainActor [weak self] in await self?.checkDisk(token: token) }
        }
    }

    /// Reads the free space and stops when it is too low. A reading that lands after the recording ended, or
    /// after another began, is ignored.
    func checkDisk(token: Int? = nil) async {
        let free = await deps.freeBytes()
        guard recordingShown, token == nil || token == generation else { return }
        lastFreeBytes = free
        evaluate(control.state)
    }

    func handle(_ event: RecorderSystemEvent) {
        guard isArmed, recordingShown, RecorderSafetyKeys.stopsOnSleepOrLock(in: deps.defaults()) else { return }
        requestStop(event == .displaySleep ? .displaySleep : .screenLocked)
    }

    private func evaluate(_ state: RecorderState) {
        let paused = pausedSince.map { max(0, Int(deps.now().timeIntervalSince($0))) } ?? 0
        if let reason = RecorderSafetyPolicy.stopReason(
            elapsedSeconds: state.elapsedSeconds, maxMinutes: RecorderSafetyKeys.maxMinutes(in: deps.defaults()),
            freeBytes: lastFreeBytes, pausedSeconds: paused) {
            requestStop(reason)
        }
    }

    private func requestStop(_ reason: RecorderSafetyPolicy.StopReason) {
        guard recordingShown, !stopRequested else { return }
        stopRequested = true
        control.stop(reason: reason.message)
    }

    private func takeSignsDown() {
        guard recordingShown else { return }
        recordingShown = false
        stopRequested = false
        pausedSince = nil
        lastFreeBytes = nil
        generation += 1
        deps.island.withdraw(RecorderLane.activityID)
        deps.statusItem.hide()
        deps.hotkey.unregister()
    }
}

// MARK: - Journal and recovery

/// What a crash would leave behind, written before the risky step and cleared after it:
/// the take being recorded (its folder name) and the staged files of exports and direct saves (their paths).
struct RecorderJournalFile: Codable, Equatable {
    var take: String?
    var startedAt: Date?
    var staged: [String] = []
}

/// A small JSON file next to the recordings. Thread-safe: staged files are noted from export queues.
final class RecorderJournal: @unchecked Sendable {
    static let fileName = ".recorder-journal.json"
    static let maxStaged = 50

    let url: URL
    private let lock = NSLock()

    init(directory: URL) {
        url = directory.appendingPathComponent(Self.fileName)
    }

    func load() -> RecorderJournalFile? {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    func noteTake(folderName: String, now: Date = Date()) {
        mutate { $0.take = folderName; $0.startedAt = now }
    }

    func settleTake(folderName: String) {
        mutate {
            guard $0.take == folderName else { return }
            $0.take = nil
            $0.startedAt = nil
        }
    }

    func noteStaged(path: String) {
        mutate {
            $0.staged.append(path)
            if $0.staged.count > Self.maxStaged { $0.staged.removeFirst($0.staged.count - Self.maxStaged) }
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    private func read() -> RecorderJournalFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RecorderJournalFile.self, from: data)
    }

    private func mutate(_ change: (inout RecorderJournalFile) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var file = read() ?? RecorderJournalFile()
        change(&file)
        if file.take == nil && file.staged.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: url, options: .atomic) }
    }
}

/// Gives back what a crash left: a staged file is deleted, a half-recorded take is saved into the person's folder
/// when it plays, deleted when it does not. Idempotent: it is driven by the journal, and the journal is cleared.
enum RecorderRecovery {
    struct Outcome: Equatable {
        /// Where a recovered recording was saved.
        var recovered: URL?
        /// A take that did not play was deleted.
        var discardedTake = false
        var removedStagedFiles = 0
    }

    /// Hidden names a staged file can carry (ours, and the one the upstream code used before patch 0953).
    static let stagedPrefixes = [RecorderSupport.stagingPrefix, ".vorssaint-partial-"]

    /// Nil when there is no journal: the step does nothing and touches no file.
    static func run(journal: RecorderJournal, root: URL, destination: () -> URL,
                    isPlayable: (URL) async -> Bool, manager: FileManager = .default) async -> Outcome? {
        guard let entry = journal.load() else { return nil }
        var outcome = Outcome()
        for path in entry.staged {
            let url = URL(fileURLWithPath: path)
            guard stagedPrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }),
                  !path.contains("/../"), manager.fileExists(atPath: path) else { continue }
            if (try? manager.removeItem(at: url)) != nil { outcome.removedStagedFiles += 1 }
        }
        if let name = entry.take, RecorderSupport.takeID(fromFolderName: name) != nil, !name.contains("/") {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            let video = folder.appendingPathComponent(RecorderSupport.takeVideoName)
            let isLink = (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            let size = (try? video.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if !isLink, manager.fileExists(atPath: folder.path) {
                if size > 0, await isPlayable(video) {
                    let target = destination()
                    let staged = RecorderSupport.stagingURL(for: target)
                    do {
                        try manager.copyItem(at: video, to: staged)
                        try manager.moveItem(at: staged, to: target)
                        try? manager.removeItem(at: folder)
                        outcome.recovered = target
                    } catch {
                        // The folder cannot be written: the take stays where it is (the 24 h sweep deletes it).
                        try? manager.removeItem(at: staged)
                    }
                } else {
                    try? manager.removeItem(at: folder)
                    outcome.discardedTake = true
                }
            }
        }
        journal.clear()
        return outcome
    }

    /// The real check: the movie has a duration (fragments are written every 10 s, so a crashed file plays up to
    /// its last one). Reads the file only, never the screen or a device.
    static func livePlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return false }
        return CMTimeGetSeconds(duration) > 0.5
    }
}

// MARK: - Live seams

/// The upstream recorder as `RecorderControlling`.
@MainActor
final class LiveRecorderControl: RecorderControlling {
    private let service: ScreenRecorderService

    init(service: ScreenRecorderService = .shared) { self.service = service }

    var state: RecorderState {
        RecorderState(isRecording: service.isRecording, isPaused: service.isPaused, elapsedSeconds: service.elapsedSeconds)
    }

    func observe(_ handler: @escaping @MainActor (RecorderState) -> Void) -> () -> Void {
        let cancellable = Publishers.CombineLatest3(service.$isRecording, service.$isPaused, service.$elapsedSeconds)
            .receive(on: DispatchQueue.main)
            .sink { recording, paused, seconds in
                MainActor.assumeIsolated {
                    handler(RecorderState(isRecording: recording, isPaused: paused, elapsedSeconds: seconds))
                }
            }
        return { cancellable.cancel() }
    }

    func stop(reason: String?) { service.stop(reason: reason) }
    func togglePause() { service.togglePause() }
    func syncWithPreferences() { service.syncWithPreferences() }
}

/// One Carbon hotkey, control-option-command-period, held only while a recording runs. It needs no permission and
/// reads no other key.
@MainActor
final class LiveRecorderStopHotkey: RecorderStopHotkeying {
    private static let signature: OSType = 0x4D49_5253  // 'MIRS'
    private static let id: UInt32 = 1
    private nonisolated(unsafe) static var handlerRef: EventHandlerRef?
    private nonisolated(unsafe) static var onPress: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?

    func register(onPress: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        Self.installHandlerIfNeeded()
        Self.onPress = onPress
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Period), UInt32(controlKey | optionKey | cmdKey),
                                         EventHotKeyID(signature: Self.signature, id: Self.id),
                                         GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Self.onPress = nil
            return false
        }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.onPress = nil
    }

    private static func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var pressed = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            }
            guard pressed.signature == LiveRecorderStopHotkey.signature, pressed.id == LiveRecorderStopHotkey.id
            else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { MainActor.assumeIsolated { LiveRecorderStopHotkey.onPress?() } }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

/// The menu bar item that exists only while a recording runs: a red dot with the elapsed time, and a menu to
/// pause or stop.
@MainActor
final class LiveRecorderStatusItem: NSObject, RecorderStatusPresenting {
    private var item: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var actions: RecorderStatusActions?

    func show(elapsed: String, paused: Bool, actions: RecorderStatusActions) {
        self.actions = actions
        if item == nil { build() }
        guard let button = item?.button else { return }
        button.image = NSImage(systemSymbolName: paused ? "pause.circle.fill" : "record.circle.fill",
                               accessibilityDescription: paused ? "Enregistrement en pause" : "Enregistrement en cours")
        button.contentTintColor = paused ? .systemOrange : .systemRed
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.title = " \(elapsed)"
        pauseItem?.title = paused ? "Reprendre l’enregistrement" : "Mettre en pause"
    }

    func hide() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        pauseItem = nil
        actions = nil
    }

    private func build() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let pause = NSMenuItem(title: "Mettre en pause", action: #selector(pausePressed), keyEquivalent: "")
        pause.target = self
        let stop = NSMenuItem(title: "Arrêter l’enregistrement  (⌃⌥⌘ .)", action: #selector(stopPressed), keyEquivalent: "")
        stop.target = self
        menu.addItem(pause)
        menu.addItem(stop)
        item.menu = menu
        self.item = item
        pauseItem = pause
    }

    @objc private func pausePressed() { actions?.togglePause() }
    @objc private func stopPressed() { actions?.stop() }
}

/// Display sleep and screen lock, from the system. Only listened to while the supervisor is armed.
@MainActor
final class LiveRecorderSystemEvents: RecorderSystemEventSource {
    func observe(_ handler: @escaping @MainActor (RecorderSystemEvent) -> Void) -> () -> Void {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let tokens: [(NotificationCenter, NSObjectProtocol)] = [
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil,
                                              queue: .main) { _ in MainActor.assumeIsolated { handler(.displaySleep) } }),
            (workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil,
                                              queue: .main) { _ in MainActor.assumeIsolated { handler(.displaySleep) } }),
            (distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil,
                                                  queue: .main) { _ in MainActor.assumeIsolated { handler(.screenLocked) } }),
        ]
        return { for (center, token) in tokens { center.removeObserver(token) } }
    }
}

// MARK: - Lane

/// Binds the ported screen recorder (`screenRecorder`, Settings page 15 "Enregistrement de l’écran").
///
/// What the registry does, all through `Runtime` so tests never touch ScreenCaptureKit, AVFoundation or a window:
/// - start (switch on, Screen Recording AND Accessibility seen by the monitor, or granted later) = recover what a
///   crash left, arm the supervisor and the journal hooks, then the upstream `syncWithPreferences` (leftover sweep,
///   the optional start shortcut). Nothing records: a recording begins only when the person starts one.
/// - stop (switch off, kill switch, safe mode, quarantine, a permission revoked) = the recording in progress is
///   stopped and SAVED to the person's folder, the supervisor takes every sign down, the start shortcut goes.
///
/// Permissions: Screen Recording and Accessibility are read, never asked (the clicks on "Autoriser" go through
/// `UserPermissionRequest`, in the feature card the page opens with). The microphone is asked only by a click on
/// the page (the toggle or its "Autoriser" row), never at a recording start (patch 0950). System audio comes from
/// the capture stream; the finer process tap is built only after a click proved System Audio Recording (patch
/// 0951; the click is the mixer's `PortMixer.requestAudioCaptureByClick`, offered on the page while the mixer is
/// on). Sharing has no server: its buttons are hidden (patches 0954 and 0955).
///
/// Safety nets, in order: the visible signs and the stop shortcut (`RecorderSafety`), the automatic stops (maximum
/// duration, under 1 GB free, display sleep or lock when chosen, a pause of 30 minutes), the journal (`take` and
/// staged files, written before the risk, cleared after it) with `recoverAtLaunch`, and the temp-then-rename of
/// every file written to the person's folder (patches 0952 and 0953).
enum RecorderLane {
    static let source = "screenRecorder"
    static let activityID = "screenRecorder.recording"
    static let pageID = "recording"

    struct Runtime {
        var recover: @MainActor () -> Void
        var arm: @MainActor () -> Void
        var disarm: @MainActor () -> Void
        /// Ends the recording in progress and saves it.
        var stopRecording: @MainActor () -> Void
        /// The upstream `syncWithPreferences` of the recorder and of the capture service (start shortcut).
        var sync: @MainActor () -> Void

        /// Builds a runtime around the pieces; the live one and the tests differ only by these.
        @MainActor static func make(control: RecorderControlling, safety: RecorderSafety,
                                    recover: @escaping @MainActor () -> Void,
                                    arm: @escaping @MainActor () -> Void = {},
                                    disarm: @escaping @MainActor () -> Void = {},
                                    syncCapture: @escaping @MainActor () -> Void = {}) -> Runtime {
            Runtime(recover: recover,
                    arm: { arm(); safety.arm() },
                    disarm: { safety.disarm(); disarm() },
                    stopRecording: { control.stop(reason: "Enregistrement arrêté : la fonction a été désactivée. La vidéo est enregistrée.") },
                    sync: { control.syncWithPreferences(); syncCapture() })
        }

        @MainActor private static let liveParts: (control: LiveRecorderControl, safety: RecorderSafety, hooks: LiveHooks) = {
            let control = LiveRecorderControl()
            let safety = RecorderSafety(control: control, dependencies: .init(
                island: .live, statusItem: LiveRecorderStatusItem(), hotkey: LiveRecorderStopHotkey(),
                events: LiveRecorderSystemEvents(),
                freeBytes: { RecorderTakeStore.shared.freeBytes() },
                now: { Date() }, defaults: { PortHost.defaults }))
            return (control, safety, LiveHooks())
        }()

        @MainActor static let live: Runtime = {
            let parts = liveParts
            return make(control: parts.control, safety: parts.safety,
                        recover: { RecorderLane.recoverAtLaunchLive() },
                        arm: { parts.hooks.install() },
                        disarm: { parts.hooks.removeQuitObserver() },
                        syncCapture: { ScreenCaptureService.shared.syncWithPreferences() })
        }()
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        recoverAtLaunchLive()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(
            "screenRecorder",
            page: PortFeaturePage(pageID: pageID) { AnyView(RecorderPage()) },
            start: {
                runtime.recover()
                runtime.arm()
                runtime.sync()
            },
            stop: {
                runtime.stopRecording()
                runtime.sync()
                runtime.disarm()
            })
    }

    // MARK: Launch recovery

    private static var didRecover = false

    /// The step `PortBridge.recoverAtLaunch` can call and the lane itself runs once at bind: what a crash left
    /// (a partial take, a staged file) is saved or deleted. Entered only when the journal exists, so a Mac where
    /// the recorder never ran touches no file.
    @MainActor static func recoverAtLaunchLive() {
        guard !didRecover else { return }
        didRecover = true
        guard let root = RecorderTakeStore.shared.recordingsRoot else { return }
        let journal = RecorderJournal(directory: root)
        guard journal.load() != nil else { return }
        Task { @MainActor in
            let strings = FeatureStrings.recorder(L10n.shared.language)
            let outcome = await RecorderRecovery.run(
                journal: journal, root: root,
                destination: { ScreenRecorderService.saveDestination(strings: strings, fileExtension: "mov") },
                isPlayable: RecorderRecovery.livePlayable)
            guard let saved = outcome?.recovered else { return }
            ActivityCenter.shared.post(IslandActivity(
                id: "screenRecorder.recovered", source: source, priority: .alert,
                leading: CompactItem(symbol: "arrow.counterclockwise.circle.fill",
                                     text: "Enregistrement récupéré : \(saved.deletingLastPathComponent().lastPathComponent)",
                                     status: .info)),
                expiresAfter: .seconds(15))
        }
    }

    /// The journal hooks of the upstream recorder and the quit handler. The hooks stay once installed: a stop that
    /// finishes after the feature went off must still settle its take.
    @MainActor final class LiveHooks {
        private var installed = false
        private var quitObserver: NSObjectProtocol?

        func install() {
            if let root = RecorderTakeStore.shared.recordingsRoot, !installed {
                installed = true
                let journal = RecorderJournal(directory: root)
                let service = ScreenRecorderService.shared
                service.onTakeStarted = { journal.noteTake(folderName: $0.folder.lastPathComponent) }
                service.onTakeSettled = { journal.settleTake(folderName: $0.folder.lastPathComponent) }
                RecorderSupport.stagedObserver = { journal.noteStaged(path: $0.path) }
            }
            guard quitObserver == nil else { return }
            // Quitting mid-recording asks for a stop; the file is finalised by the journal's recovery if the
            // process ends first (the movie is written in fragments).
            quitObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ScreenRecorderService.shared.stop(reason: nil) }
            }
        }

        func removeQuitObserver() {
            if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
            quitObserver = nil
        }
    }
}

// MARK: - Page 15: Enregistrement de l’écran

/// The ported recorder settings (start button, countdown, sound, folder, quality, GIF) with the start shortcut
/// above and the safety section below. The switch and the permission card come from the card the page opens with.
struct RecorderPage: View {
    var body: some View {
        Form {
            RecorderShortcutSection()
            ScreenRecordingCaptureSettings()
            RecorderSafetySection()
        }
        .formStyle(.grouped)
    }
}

private struct RecorderShortcutSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var capture = ScreenCaptureService.shared
    @AppStorage(DefaultsKey.recorderShortcutEnabled) private var enabled = false

    var body: some View {
        Section {
            Toggle(GlobalShortcutRole.screenRecorder.title(l10n.s), isOn: $enabled)
                .onChange(of: enabled) { _, _ in capture.syncWithPreferences() }
            ShortcutPreferenceRow(role: .screenRecorder, isEnabled: enabled) { capture.syncWithPreferences() }
            if enabled, capture.toolShortcutRegistrationFailures.contains(.recording) {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Raccourci de démarrage")
        }
    }
}

private struct RecorderSafetySection: View {
    @AppStorage(RecorderSafetyKeys.maxMinutes) private var maxMinutes = RecorderSafetyPolicy.defaultMaxMinutes
    @AppStorage(RecorderSafetyKeys.stopOnSleepOrLock) private var stopOnSleepOrLock = true
    @State private var audioState = MixerAudioCapture.currentState()

    var body: some View {
        Section {
            Picker("Durée maximale", selection: $maxMinutes) {
                ForEach(RecorderSafetyPolicy.allowedMaxMinutes, id: \.self) { minutes in
                    Text(Self.label(minutes: minutes)).tag(minutes)
                }
            }
            Toggle("Arrêter si l’écran se met en veille ou se verrouille", isOn: $stopOnSleepOrLock)
            Text("Un point rouge reste visible dans l’îlot et dans la barre des menus tant qu’un enregistrement tourne. "
                 + "Pour l’arrêter depuis n’importe quelle app : ⌃⌥⌘ . L’enregistrement s’arrête aussi sous 1 Go d’espace "
                 + "libre, ou après 30 minutes de pause, et la vidéo est toujours enregistrée.")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The finer capture of the Mac's sound shares the mixer's "Enregistrement audio du système" grant: its click
            // is the mixer's (one probe tap in the whole app, behind the mixer's switch), so the row needs the mixer on.
            if audioState.canRequest, AppFeature.mixer.isAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Son du Mac, capture fine (facultatif)")
                        Spacer()
                        Button("Autoriser") {
                            PortMixer.requestAudioCaptureByClick()
                            audioState = MixerAudioCapture.currentState()
                        }
                    }
                    Text("Sans cette autorisation, le son du Mac est pris dans la capture d’écran, sans autre permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sécurité")
        }
        .onAppear {
            maxMinutes = RecorderSafetyPolicy.sanitizedMaxMinutes(maxMinutes)
            audioState = MixerAudioCapture.currentState()
        }
    }

    private static func label(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h" : "\(minutes) min"
    }
}
