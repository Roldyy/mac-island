// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

/// What `activate` did. Anything but `.started` / `.alreadyRunning` swallowed nothing.
enum CleaningStartOutcome: Equatable {
    case started, alreadyRunning, featureOff, needsAccessibility, refused
}

/// "Cleaning mode" temporarily locks the keyboard so the user can wipe it down
/// without typing gibberish, then restores it on a deliberate gesture. The lock
/// is a HID-level event tap that swallows key events before the system handles
/// them, including keyboard system keys such as brightness, media and volume.
/// The very same tap watches for the unlock gesture, so there is always a way
/// back.
///
/// Ways out (Mac Island keeps the upstream two and adds the rest, so nobody is ever stranded):
///   1. press Escape five times in a row,
///   2. click Unlock on the overlay (pointer movement and clicks stay available),
///   3. hold Escape for 3 seconds,
///   4. wait: it ends by itself after 60 seconds, on the tap callback's own clock too,
///   5. the system switches the tap off, or Accessibility is taken away: it ends at once,
///   6. the app quits, the feature is switched off, the kill switch or safe mode stops it, or the session is
///      switched away.
/// The lock is only an event tap owned by this process and nothing is written to disk, so a crash or a signal
/// that kills the process takes the lock with it: there is no marker to recover.
///
/// Requires Accessibility, like the app's other event taps. If it is missing the
/// tap can't be created, so we never lock the keyboard with no way to unlock it.
final class CleaningModeManager: ObservableObject {
    /// Everything the manager reaches outside itself, so a test can drive it with a fake tap, a clock and no
    /// window. `live` is the real thing.
    struct Environment {
        var makeTap: () -> CleaningEventTapping
        var now: () -> Date
        var uptime: () -> TimeInterval
        /// Accessibility, probed read-only: never a prompt.
        var isTrusted: () -> Bool
        /// The registry's verdict for the feature (switch, kill switch, safe mode, quarantine).
        var isAllowed: () -> Bool
        var showOverlays: (CleaningModeManager) -> Void
        var hideOverlays: (CleaningModeManager) -> Void
        /// The other input services that must not filter while the lock is up, and their return.
        var suspendOthers: () -> Void
        var resumeOthers: () -> Void
        /// Tells the person Accessibility is missing (an alert that opens System Settings; no system prompt).
        var guideToAccessibility: () -> Void
        /// A repeating timer drives the countdown; a test calls `tick()` itself.
        var runsTimer: Bool
        /// Where `willTerminate` is heard.
        var notifications: NotificationCenter

        static var live: Environment {
            Environment(
                makeTap: { SystemCleaningTap() },
                now: Date.init,
                uptime: { ProcessInfo.processInfo.systemUptime },
                isTrusted: { AXIsProcessTrusted() },
                isAllowed: { AppFeature.cleaningMode.isAvailable },
                showOverlays: { $0.showSystemOverlays() },
                hideOverlays: { $0.hideSystemOverlays() },
                suspendOthers: { CleaningModeManager.suspendOtherInputServices() },
                resumeOthers: { CleaningModeManager.resumeOtherInputServices() },
                guideToAccessibility: { CleaningModeManager.promptForAccessibility() },
                runsTimer: true,
                notifications: .default)
        }
    }

    static let shared = CleaningModeManager()

    private static let escapeKeyCode: Int64 = 53

    @Published private(set) var isActive = false
    /// Consecutive Escape presses so far (0...unlockThreshold). The
    /// overlay shows this as progress.
    @Published private(set) var unlockProgress = 0
    /// Whole seconds before the automatic end, for the overlay and the island.
    @Published private(set) var remainingSeconds = Int(CleaningPolicy.maxDuration)

    /// Deliberate Escape presses needed to unlock. Other keys reset the count so
    /// wiping the keyboard cannot complete the gesture accidentally.
    let unlockThreshold = 5

    /// Called on the main thread with the seconds left, each quarter second, and once when cleaning ends.
    var onTick: ((Int) -> Void)?
    var onEnd: ((CleaningEnd) -> Void)?
    /// Why the last period ended; nil while running or before the first one.
    private(set) var lastEnd: CleaningEnd?

    private let environment: Environment
    private var tap: CleaningEventTapping?
    private var policy: CleaningPolicy?
    private var deadline: TimeInterval = 0
    private var timer: Timer?
    private var overlays: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var shouldRestoreSuspendedFeaturesOnSessionReturn = false
    // Mouse events still pass through Cleaning Mode. We only remember the
    // down/up lifecycle so teardown never cuts a click in half.
    private var mouseReleaseGate = CleaningMouseReleaseGate()
    /// Ends a user unlock's wait for a release this tap never sees.
    private var releaseDeadline: DispatchWorkItem?

    /// The unlock-gesture state machine (pure, unit-tested separately).
    /// The 6s press window forgives hesitant, deliberate presses — at 2s a user
    /// pressing Escape slower than once per two seconds could never unlock
    /// (progress restarted at 1 on every press). The window's one remaining job
    /// is rejecting five isolated Esc-only contacts spread across a long wipe:
    /// every other key resets the count — modifiers included, they reach the
    /// counter as flags-changed events — and auto-repeat never counts, but a
    /// cloth can strike Escape alone. Widening to 6s weakens that guard on
    /// purpose — a gesture a deliberate user cannot complete protects nothing.
    private lazy var unlock = CleaningUnlockCounter(requiredKeyCode: Self.escapeKeyCode,
                                                    threshold: unlockThreshold,
                                                    pressWindow: 6.0)

    init(environment: Environment = .live) {
        self.environment = environment
        // A switched-away login session cannot keep a filter tap in the input
        // chain. Cleaning is a temporary local state, so leaving the session
        // ends it; suspended features resume only after this session returns.
        SessionActivity.shared.onChange { [weak self] active in
            guard let self else { return }
            if active {
                guard self.shouldRestoreSuspendedFeaturesOnSessionReturn else { return }
                self.shouldRestoreSuspendedFeaturesOnSessionReturn = false
                self.environment.resumeOthers()
            } else if self.isActive {
                self.finishDeactivation(.sessionLeft, restoreSuspendedFeatures: false)
            }
        }
        // The lock must never outlive the app, whoever asks it to quit.
        terminateObserver = environment.notifications.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stop(.quit) }
    }

    deinit {
        if let terminateObserver { environment.notifications.removeObserver(terminateObserver) }
    }

    func toggle() {
        if isActive { deactivate() } else { activate() }
    }

    /// Starts the lock. No-op (and guides the user) when Accessibility is missing,
    /// because without the tap there would be no way to unlock the keyboard.
    /// `guideWhenMissing` is false for a caller that reports it its own way (the Home button).
    @discardableResult
    func activate(guideWhenMissing: Bool = true) -> CleaningStartOutcome {
        guard !isActive else { return .alreadyRunning }
        // The one gate every entry point shares (panel, Settings, Home): the registry's verdict.
        guard environment.isAllowed() else { return .featureOff }
        // Check Accessibility explicitly (same gate the other event taps use) so a
        // missing grant is reported clearly, rather than inferred from a nil tap.
        guard environment.isTrusted() else {
            if guideWhenMissing { environment.guideToAccessibility() }
            return .needsAccessibility
        }
        mouseReleaseGate.reset()
        let newTap = environment.makeTap()
        let begin = environment.now()
        deadline = environment.uptime() + CleaningPolicy.maxDuration
        guard newTap.start(deliver: { [weak self] input in self?.handle(input) ?? false }) else { return .refused }
        tap = newTap
        // Debounce must not filter while the lock is up: its tap can run ahead
        // of ours (head-insert order depends on creation order) and would eat
        // the repeated same-key presses the unlock gesture counts on.
        // Wiping the trackpad is nothing but stray three-finger contacts, a stray side button
        // must not type a combination into the frontmost app, and the radial wheel must not
        // open over the overlay: every input service that could act steps aside.
        environment.suspendOthers()
        unlock.reset()
        unlockProgress = 0
        policy = CleaningPolicy(start: begin)
        lastEnd = nil
        remainingSeconds = Int(CleaningPolicy.maxDuration)
        isActive = true
        startTimer()
        onTick?(remainingSeconds)
        environment.showOverlays(self)
        return .started
    }

    /// The person asked to unlock. If a click began while the overlay was up, the overlay and tap stay until its
    /// real mouse-up passes through (a release is never manufactured), for at most 5 seconds.
    func deactivate() {
        guard isActive else { return }
        armReleaseDeadline()
        guard mouseReleaseGate.requestDeactivation() else { return }
        scheduleUserDeactivation()
    }

    /// Ends cleaning NOW, whatever the mouse is doing: app quit, the feature stopped by the registry (switch off,
    /// kill switch, safe mode), the system teardown of a permission reset. Idempotent.
    func stop(_ reason: CleaningEnd = .stopped) {
        guard isActive else { return }
        finishDeactivation(reason, restoreSuspendedFeatures: true)
    }

    /// Permission teardown must remove the tap before Accessibility is reset.
    func deactivateForSystemTeardown() { stop(.stopped) }

    /// Every unlock path waits on the gate, and the overlay can cover the menu
    /// bar, so the wait is bounded. Nothing is posted; it only stops waiting.
    private func armReleaseDeadline() {
        guard releaseDeadline == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.releaseDeadline = nil
            guard self.isActive, self.mouseReleaseGate.releaseWaitExpired() else { return }
            self.scheduleUserDeactivation()
        }
        releaseDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CleaningMouseReleaseGate.releaseWaitLimit, execute: work)
    }

    private func scheduleUserDeactivation() {
        // Even when no button is currently held, leave the AppKit control action
        // before unmapping its non-activating panel. A new press may arrive before
        // this block runs, so keep the request pending until teardown completes.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.mouseReleaseGate.deactivationPending,
                  self.mouseReleaseGate.pressedButtons.isEmpty else { return }
            self.finishDeactivation(.unlocked, restoreSuspendedFeatures: true)
        }
    }

    private func finishDeactivation(_ reason: CleaningEnd, restoreSuspendedFeatures: Bool) {
        guard isActive else { return }
        releaseDeadline?.cancel()
        releaseDeadline = nil
        timer?.invalidate()
        timer = nil
        mouseReleaseGate.reset()
        removeTap()
        environment.hideOverlays(self)
        unlock.reset()
        unlockProgress = 0
        policy?.end(reason)
        policy = nil
        lastEnd = reason
        isActive = false
        remainingSeconds = Int(CleaningPolicy.maxDuration)
        onEnd?(reason)
        guard restoreSuspendedFeatures else {
            shouldRestoreSuspendedFeaturesOnSessionReturn = true
            return
        }
        shouldRestoreSuspendedFeaturesOnSessionReturn = false
        // Each owner reads its current availability, preference and permission,
        // so a feature changed while Cleaning Mode was active stays changed.
        environment.resumeOthers()
    }

    // MARK: - Clock

    private func startTimer() {
        guard environment.runsTimer else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// One look at the clocks and at the tap. Every 0.25 s while cleaning (a test calls it itself).
    func tick() {
        guard isActive, var current = policy else { return }
        let now = environment.now()
        let ended = current.tick(at: now)
        policy = current
        if let ended {
            finishDeactivation(ended, restoreSuspendedFeatures: true)
            return
        }
        // Accessibility taken away, or the tap switched off by macOS: give the keyboard back at once.
        if !environment.isTrusted() || tap?.isEnabled == false {
            finishDeactivation(.tapFailed, restoreSuspendedFeatures: true)
            return
        }
        remainingSeconds = current.remainingSeconds(at: now)
        onTick?(remainingSeconds)
    }

    // MARK: - Event tap

    private func removeTap() {
        tap?.stop()
        tap = nil
    }

    /// The tap callback's decision: true swallows the event. It runs on the main thread (the tap's run-loop
    /// source lives on the main run loop), so it can touch published state and AppKit directly.
    func handle(_ input: CleaningInput) -> Bool {
        // A callback that outlives the lock lets everything through.
        guard isActive else { return false }

        // The system disables taps that stall or are switched off; do not re-arm a lock the system took away.
        // Failing open is the safe side of a keyboard lock.
        if input == .tapDisabled {
            let restore = SessionActivity.shared.isActive
            finishDeactivation(.tapFailed, restoreSuspendedFeatures: restore)
            return false
        }

        // Last line of defence on the monotonic clock: past the deadline nothing is swallowed, even if the
        // timer has not fired yet.
        guard CleaningPolicy.swallows(uptime: environment.uptime(), deadline: deadline) else {
            finishDeactivation(.timeout, restoreSuspendedFeatures: true)
            return false
        }

        switch input {
        case let .mouseButton(button, isDown):
            // Mouse clicks are never locked. Observe only their boundaries so a
            // user-requested teardown can wait for a matching real release.
            if isDown {
                mouseReleaseGate.buttonDown(button)
            } else if mouseReleaseGate.buttonUp(button) {
                // The callback is running on this tap's run loop. Removing the tap
                // here would invalidate it from its own callback stack, so finish on
                // the next main-loop turn after the real release has propagated.
                scheduleUserDeactivation()
            }
            return false
        case let .key(code, isDown, isRepeat):
            if code == CleaningPolicy.escapeKeyCode {
                policy?.escape(down: isDown, isRepeat: isRepeat, at: environment.now())
            }
            // Feed key-downs to the unlock state machine. Auto-repeat (holding a key)
            // is ignored, so only distinct, deliberate taps of the same key count.
            if isDown { registerUnlockKeyDown(code: code, isRepeat: isRepeat) }
        case let .flagsChanged(code):
            // Shift, control, option, command, fn and caps lock arrive here rather
            // than as key-downs, and they are the keys nearest Escape — a cloth
            // resting on them must reset the count like any other key. Both the
            // press and the release report the same key code and neither is
            // Escape, so each one resets and the pair is idempotent. Modifiers
            // never auto-repeat.
            registerUnlockKeyDown(code: code, isRepeat: false)
        case let .systemKey(key):
            if key.isKeyDown { registerUnlockKeyDown(code: key.code, isRepeat: key.isRepeat) }
        case .other, .tapDisabled:
            break
        }

        // Swallow keys, scrolling and trackpad gestures while the lock is on.
        // Pointer movement and clicks remain available for the Unlock button.
        return true
    }

    private func registerUnlockKeyDown(code: Int64, isRepeat: Bool) {
        let unlocked = unlock.registerKeyDown(code: code,
                                              time: ProcessInfo.processInfo.systemUptime,
                                              isRepeat: isRepeat)
        unlockProgress = unlock.progress
        if unlocked {
            // deactivate() only records the request here; actual teardown is
            // scheduled after this tap callback has returned.
            deactivate()
        }
    }

    // MARK: - Other input services

    /// The input services of other lanes that step aside while the lock is up. Only a feature a lane bound AND the
    /// registry lets run is touched, and resumed through the same `FeatureRuntime` path afterwards: an unbound
    /// feature has no running service, and `syncWithPreferences` would start one from its stored switch.
    private static let steppingAside: [(AppFeature, () -> Void)] = [
        (.keyboardDebounce, { KeyboardDebounceService.shared.suspend() }),
        (.mouseClickDebounce, { MouseClickDebounceService.shared.suspend() }),
        (.middleClick, { MiddleClickService.shared.suspend() }),
        (.mouseNavigation, { MouseNavigationService.shared.suspend() }),
        (.mouseButtonShortcuts, { MouseButtonShortcutService.shared.suspend() }),
        (.radialMenu, { RadialMenuService.shared.suspend() }),
    ]

    static func suspendOtherInputServices() {
        for (feature, suspend) in steppingAside where PortShortcutOwnership.isRunning(feature) { suspend() }
    }

    static func resumeOtherInputServices() {
        FeatureRuntime.shared.sync(steppingAside.map(\.0).filter(PortShortcutOwnership.isRunning))
    }

    // MARK: - Overlay

    private func showSystemOverlays() {
        installScreenObserver()
        showOverlays()
    }

    private func hideSystemOverlays() {
        removeScreenObserver()
        hideOverlays()
    }

    private func showOverlays() {
        let frames = NSScreen.screens.map(\.frame)
        let targetFrames = frames.isEmpty
            ? [NSRect(x: 0, y: 0, width: 800, height: 600)]
            : frames
        // Screen notifications can arrive in bursts even when the frames stay
        // unchanged. Reuse those panels so the overlay never flashes or drops a click.
        var reusable = overlays
        overlays = targetFrames.map { frame in
            if let index = reusable.firstIndex(where: { $0.frame == frame }) {
                return reusable.remove(at: index)
            }
            return makeOverlay(frame: frame)
        }
        reusable.forEach { $0.orderOut(nil) }
    }

    private func makeOverlay(frame: NSRect) -> NSPanel {
        let panel = OverlayPanel(contentRect: frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Above the menu bar and full-screen apps — the shielding level macOS uses
        // for its own lock-style windows.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // acceptsFirstMouse so the Unlock button fires on the very first click even
        // though the panel never becomes key or activates the app — otherwise that
        // click would just be absorbed as the window-activating click.
        let host = OverlayHostingView(rootView: CleaningOverlayView())
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        return panel
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard self?.isActive == true else { return }
            self?.showOverlays()
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    /// Hosting view that accepts the first click into the (non-key, non-activating)
    /// overlay panel, so the Unlock button works without a throwaway activating click.
    private final class OverlayHostingView: NSHostingView<CleaningOverlayView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    /// Opens the Accessibility pane through `Permissions` (which never shows the system prompt) after an alert.
    private static func promptForAccessibility() {
        let strings = L10n.shared.s
        let alert = NSAlert()
        alert.messageText = strings.cleaningNeedsAxTitle
        alert.informativeText = strings.cleaningNeedsAxBody
        alert.addButton(withTitle: strings.permissionOpenSettings)
        alert.addButton(withTitle: strings.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.shared.requestAccessibility()
            Permissions.shared.openAccessibilitySettings()
        }
    }
}
