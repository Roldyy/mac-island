// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W4A (screenshot). The lane owns this file.

import AppKit
import SwiftUI

// MARK: - Lane

/// Binds the ported screenshot tool (`screenshot`, Settings page 14 "Capture d'écran"): area, window and full-screen
/// capture with the freeze overlay and the HUD, the recent captures list, the annotation editor and the scrolling
/// capture. One registry feature, new to Mac Island (its id is the upstream raw id, so a migrated
/// `shell.enabled.screenshot` is the switch the registry reads). The Home "Capture" tile and the quick-access button
/// call `PortScreenshot` and fall back to our old `screencapture -i` only while this feature is off.
///
/// What the registry does, all through `Runtime` so tests never touch ScreenCaptureKit, a hotkey or a window:
/// - start (switch on AND Screen Recording seen by the monitor: `PortFeatureBinding` never starts without it and
///   the registry restarts the feature on the grant) = the three upstream services re-read their preferences and
///   register the shortcuts the person turned on. Every shortcut is off until chosen, and the defaults sit on the
///   control-option-command layer, never on the system's shift-command 3, 4 and 5.
/// - stop (switch off, kill switch, safe mode, quarantine, Screen Recording revoked) = a selection or countdown on
///   screen is closed first, then the services re-read availability (which is false by now): their hotkeys leave,
///   open editors, pins and the preview are closed, the scrolling task is cancelled; the drag temp folders go.
///
/// Shared services stay shared: the recorder, text and colour lanes (4B, 4C) use the same chooser, so a stop here
/// re-syncs it (it keeps their hotkeys) and never calls its `suspend()`.
///
/// Nothing here prompts: Screen Recording is read from the host, the Settings card and the Home tile open the
/// System Settings pane (`UserPermissionRequest` on the click path), and the share/upload service is a stub that
/// never reaches a network (its screens are hidden, `ScreenshotShareService.isAvailable` is false).
enum ScreenshotLane {
    /// Our Settings page (`SettingsPageCatalog`, row 14).
    static let pageID = "screenshot"
    static let featureID = "screenshot"

    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        /// The chooser's shortcuts (one per tool): re-reads which tools are available.
        var syncChooser: @MainActor () -> Void
        /// The screenshot service: full screen, last capture and clipboard shortcuts; tears surfaces down when off.
        var syncScreenshot: @MainActor () -> Void
        /// The recent captures shortcut and palette.
        var syncRecent: @MainActor () -> Void
        /// Closes the selection or countdown of the chooser, whatever the preferences say.
        var cancelSelection: @MainActor () -> Void
        /// Removes the temporary drag folders.
        var removeTemporaryFiles: @MainActor () -> Void

        static let live = Runtime(
            syncChooser: { ScreenCaptureService.shared.syncWithPreferences() },
            syncScreenshot: { ScreenshotService.shared.syncWithPreferences() },
            syncRecent: { RecentCaptureService.shared.syncWithPreferences() },
            cancelSelection: { ScreenCaptureService.shared.cancelActiveSelection() },
            removeTemporaryFiles: { ScreenshotSupport.removeTemporaryDragDirectories() })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installActions()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(
            "screenshot",
            page: PortFeaturePage(pageID: pageID) { AnyView(ScreenCaptureSettings()) },
            start: {
                runtime.syncScreenshot()
                runtime.syncChooser()
                runtime.syncRecent()
            },
            stop: {
                runtime.cancelSelection()  // the overlay first: it is the thing that holds the screen
                runtime.syncScreenshot()
                runtime.syncChooser()
                runtime.syncRecent()
                runtime.removeTemporaryFiles()
            })
    }

    private static var didInstallActions = false

    /// The command-bar and quick-action keys other surfaces may look up by name.
    @MainActor private static func installActions() {
        guard !didInstallActions else { return }
        didInstallActions = true
        PortBridge.register(actionKey: "screenshot.area") { MainActor.assumeIsolated { _ = PortScreenshot.beginAreaCapture() } }
        PortBridge.register(actionKey: "screenshot.scrolling") {
            MainActor.assumeIsolated { _ = PortScreenshot.beginScrollingCapture() }
        }
        PortBridge.register(actionKey: "screenshot.recent") { MainActor.assumeIsolated { PortScreenshot.showRecentCaptures() } }
    }
}

// MARK: - What the host calls

/// The screenshot tool as the host sees it: the Home "Capture" tile and the quick-access button start a capture here,
/// the shell can host the recent captures list. Nothing in this enum prompts, writes a file or reads the screen: it
/// decides, then hands over to the ported chooser.
public enum PortScreenshot {
    public enum StartResult: Equatable, Sendable {
        /// The chooser (area, window, full screen) is on screen or its countdown runs.
        case started
        /// The registry holds the feature down: switch off, kill switch, safe mode, quarantine.
        case featureOff
        /// Screen Recording is missing: nothing was shown, nothing was asked. The caller opens the pane on a click.
        case needsScreenRecording
        /// Another capture surface (ours, the recorder, text or colour) owns the screen.
        case busy
    }

    /// The seams of the host side. The app uses `live`; tests swap it, so no test reaches ScreenCaptureKit.
    struct Hooks {
        var isRunning: () -> Bool
        var hasScreenRecording: () -> Bool
        var isBusy: @MainActor () -> Bool
        var startArea: @MainActor () -> Void
        var startScrolling: @MainActor () -> Void
        var showRecent: @MainActor () -> Void

        static let live = Hooks(
            isRunning: { PortHost.availability?(ScreenshotLane.featureID) == true },
            hasScreenRecording: { PortHost.permissionState.value.screenRecording },
            isBusy: { ScreenshotSelectionController.isSessionOnScreen || ScreenCaptureService.shared.hasActiveSession },
            startArea: { ScreenCaptureService.shared.capture(initial: .screenshot) },
            startScrolling: { ScreenshotService.shared.captureScrolling() },
            showRecent: { RecentCaptureService.shared.showHistoryWindow() })
    }

    @MainActor static var hooks = Hooks.live

    /// True while the registry lets the ported screenshot tool run.
    @MainActor public static var isRunning: Bool { hooks.isRunning() }

    /// The Screen Recording grant as the permission monitor last read it.
    @MainActor public static var hasScreenRecording: Bool { hooks.hasScreenRecording() }

    /// Opens the chooser, on the screenshot mode. Never prompts: a missing permission is reported, not requested.
    @MainActor @discardableResult
    public static func beginAreaCapture() -> StartResult {
        guard let refusal = refusal() else {
            hooks.startArea()
            return .started
        }
        return refusal
    }

    /// Opens the scrolling capture (the region picker, then the scrolling run).
    @MainActor @discardableResult
    public static func beginScrollingCapture() -> StartResult {
        guard let refusal = refusal() else {
            hooks.startScrolling()
            return .started
        }
        return refusal
    }

    /// The floating "Captures récentes" palette. Silent when the feature is off.
    @MainActor public static func showRecentCaptures() {
        guard hooks.isRunning() else { return }
        hooks.showRecent()
    }

    /// The recent captures list, for the shell to host (a Settings section, an island tab). It shows only what the
    /// running features may show.
    @MainActor public static func recentCapturesView() -> AnyView {
        AnyView(RecentCapturesView(onClose: nil).defaultAppStorage(PortHost.defaults))
    }

    @MainActor private static func refusal() -> StartResult? {
        guard hooks.isRunning() else { return .featureOff }
        guard hooks.hasScreenRecording() else { return .needsScreenRecording }
        if hooks.isBusy() { return .busy }
        return nil
    }
}

// MARK: - Overlay close rules

/// The rules that take a capture overlay off the screen. The overlay is a full-screen window per display that
/// holds the keyboard and the mouse, so it must never outlive the situation it was made for: Escape, a change of
/// displays (the frozen picture and the panels no longer match the screens), the app losing the focus, and a
/// 60 s timeout (a capture nobody finishes, a frozen picture that never arrives).
///
/// Main thread only (notifications and the timer arrive there). The guard is armed by `ScreenshotSelectionController.begin` and disarmed by its `finish`. Escape is handled by
/// the controller's own key monitors (local and global); `Reason.escape` is here so the rule table is one place.
final class ScreenshotOverlayGuard {
    enum Reason: Equatable, Sendable { case escape, displayChange, appDeactivated, timeout }

    static let timeout: TimeInterval = 60
    static let escapeKeyCode: UInt16 = 53

    /// Schedules a block after a delay and returns what cancels it. Tests pass a fake clock.
    typealias Schedule = (_ delay: TimeInterval, _ block: @escaping () -> Void) -> () -> Void

    static let liveSchedule: Schedule = { delay, block in
        let work = DispatchWorkItem { block() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }

    /// The reason a key closes the overlay, nil for every other key.
    static func reason(forKeyCode keyCode: UInt16) -> Reason? { keyCode == escapeKeyCode ? .escape : nil }

    private let center: NotificationCenter
    private let timeout: TimeInterval
    private let schedule: Schedule
    private let onClose: (Reason) -> Void
    private var observers: [NSObjectProtocol] = []
    private var cancelTimer: (() -> Void)?
    private var deactivationObserver: NSObjectProtocol?
    private(set) var isArmed = false
    private(set) var closedBy: Reason?

    init(center: NotificationCenter = .default, timeout: TimeInterval = ScreenshotOverlayGuard.timeout,
         schedule: @escaping Schedule = ScreenshotOverlayGuard.liveSchedule,
         onClose: @escaping (Reason) -> Void) {
        self.center = center
        self.timeout = timeout
        self.schedule = schedule
        self.onClose = onClose
    }

    /// Display changes and the timeout. Idempotent.
    func start() {
        guard !isArmed else { return }
        isArmed = true
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                            queue: nil) { [weak self] _ in self?.deliver(.displayChange) })
        cancelTimer = schedule(timeout) { [weak self] in self?.close(.timeout) }
    }

    /// Losing the focus closes the overlay, but only once the panels are on screen: the island closing or the
    /// settings window handing over the focus while the capture starts must not cancel it.
    func armDeactivation() {
        guard isArmed, deactivationObserver == nil else { return }
        deactivationObserver = center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                  queue: nil) { [weak self] _ in self?.deliver(.appDeactivated) }
    }

    /// Removes every observer and the timer. Idempotent; nothing fires afterwards.
    func stop() {
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        if let deactivationObserver { center.removeObserver(deactivationObserver) }
        deactivationObserver = nil
        cancelTimer?()
        cancelTimer = nil
        isArmed = false
    }

    /// A key reached the overlay. True when it closed it.
    @discardableResult
    func handleKey(_ keyCode: UInt16) -> Bool {
        guard isArmed, let reason = Self.reason(forKeyCode: keyCode) else { return false }
        close(reason)
        return true
    }

    private func deliver(_ reason: Reason) {
        if Thread.isMainThread {
            close(reason)
        } else {
            DispatchQueue.main.async { [weak self] in self?.close(reason) }
        }
    }

    private func close(_ reason: Reason) {
        guard isArmed else { return }
        closedBy = reason
        stop()
        onClose(reason)
    }

    deinit {
        // Observers hold only `[weak self]`, but a timer or an observer must not outlive the guard.
        for observer in observers { center.removeObserver(observer) }
        if let deactivationObserver { center.removeObserver(deactivationObserver) }
    }
}

// MARK: - Saving

/// Where a capture lands when its folder cannot take it. The destination is the person's folder when it exists,
/// otherwise the Desktop (`ScreenshotService.saveDestination`); this covers the third case, a folder that exists
/// and refuses the write (read-only volume, permission). The capture is then written to the Desktop under a name
/// that overwrites nothing, instead of being lost with a beep. The chosen folder itself is never created.
enum ScreenshotSaveFallback {
    static var desktop: URL? { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first }

    /// Returns the file actually written. Throws the first error when there is no other place to try.
    static func write(_ data: Data, to url: URL, fallbackFolder: URL? = ScreenshotSaveFallback.desktop,
                      write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                      exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) throws -> URL {
        do {
            try write(data, url)
            return url
        } catch {
            guard let folder = fallbackFolder,
                  folder.standardizedFileURL.path != url.deletingLastPathComponent().standardizedFileURL.path
            else { throw error }
            let name = ScreenshotSupport.uniqueFileName(url.lastPathComponent) { candidate in
                exists(folder.appendingPathComponent(candidate))
            }
            let fallback = folder.appendingPathComponent(name)
            try write(data, fallback)
            return fallback
        }
    }
}

// MARK: - The shelf

/// The Shelf as the capture tool sees it. "Ajouter à l'étagère" (the editor's menu entry and the automatic option)
/// writes into the ported `ShelfService`, which lane W5B bound: the shelf the person sees (the island's Étagère tab
/// and the floating shelf) is that same service, so a capture sent there lands where they look. The entries also
/// need the shelf feature on (`shelfAvailable`), which the editor and the page check.
enum ScreenshotShelfBridge {
    /// True now that the ported shelf is bound (W5B flipped it).
    static let isHosted = true

    static let unavailableReason =
        "L’étagère de Mac Island n’accepte pas encore les captures : cette option est désactivée pour l’instant."
}

// MARK: - Private files

/// The permissions of the files a capture leaves behind. A capture is a picture of the person's screen: its temporary
/// folders belong to the user alone (0700) and its files too (0600), and they are cleaned up.
enum ScreenshotPrivateFiles {
    static let folderPermissions: Int = 0o700
    static let filePermissions: Int = 0o600

    /// Makes `folder` private to the user. A failure is not fatal: the folder is already inside a per-user
    /// directory.
    static func restrict(folder: URL, manager: FileManager = .default) {
        try? manager.setAttributes([.posixPermissions: folderPermissions], ofItemAtPath: folder.path)
    }

    static func restrict(file: URL, manager: FileManager = .default) {
        try? manager.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: file.path)
    }
}
