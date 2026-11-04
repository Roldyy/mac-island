// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import ApplicationServices
import CoreGraphics

final class FocusFollowsMouseService {
    static let shared = FocusFollowsMouseService()

    private let queryQueue = DispatchQueue(label: "be.roldy.macisland.focus-follows-mouse")
    private var timer: Timer?
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var state = FocusFollowsMouseState()
    /// Read when the feature starts and when a preference changes, never on a mouse move; nil while off.
    private var preferences: FocusFollowsMousePreferences?
    private var settle = FocusFollowsMouseSettle()
    /// The newest pointer position seen between two processed moves (moves are processed at most 20 times a second).
    private var pendingPoint: CGPoint?
    private var isRunning = false

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.focusFollowsMouse.isAvailable
            && PortHost.defaults.bool(forKey: DefaultsKey.focusFollowsMouseEnabled)
        if SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    func preferencesDidChange() {
        preferences?.refresh()
    }

    func stop() {
        resetMovement()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        preferences = nil
        isRunning = false
    }

    private func start() {
        guard !isRunning else {
            preferencesDidChange()
            return
        }
        preferences = FocusFollowsMousePreferences(read: Self.readPreferences)
        guard let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
            handler: { [weak self] event in
                guard let point = event.cgEvent?.location else { return }
                self?.recordMovement(to: point)
            }
        ) else { return }
        self.mouseMonitor = mouseMonitor

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            self?.resetMovement()
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            self?.resetMovement()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.resetMovement() })
        // The raise and wait-for-stop switches live in the settings views and do not call us: pick them up here.
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: PortHost.defaults, queue: .main) { [weak self] _ in
            self?.preferencesDidChange()
        })
        isRunning = true
    }

    private static func readPreferences() -> (raise: Bool, waitForStop: Bool, delayMilliseconds: Int) {
        (PortHost.defaults.bool(forKey: DefaultsKey.focusFollowsMouseRaise),
         PortHost.defaults.bool(forKey: DefaultsKey.focusFollowsMouseWaitForStop),
         PortHost.defaults.integer(forKey: DefaultsKey.focusFollowsMouseDelay))
    }

    private func recordMovement(to point: CGPoint) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.recordMovement(to: point)
            }
            return
        }
        guard isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard settle.shouldProcessMove(at: now) else {
            pendingPoint = point
            return
        }
        processMovement(to: point, at: now)
    }

    private func processMovement(to point: CGPoint, at now: TimeInterval) {
        guard isRunning, let preferences else { return }
        pendingPoint = nil
        state.recordMovement(to: point, at: now,
                             windowID: preferences.waitsForStop ? nil : Self.receivingWindow(at: point))
        armSettleTimerIfNeeded()
    }

    /// One one-shot timer per wait, never a repeating one.
    private func armSettleTimerIfNeeded() {
        guard isRunning, let preferences,
              let wait = settle.armIfNeeded(state: state, now: ProcessInfo.processInfo.systemUptime,
                                            delayMilliseconds: preferences.delayMilliseconds)
        else { return }
        scheduleSettleTimer(after: wait)
    }

    private func scheduleSettleTimer(after wait: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in self?.settleTimerFired() }
        timer.tolerance = min(0.02, wait / 5)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func settleTimerFired() {
        timer = nil
        guard isRunning, let preferences else { return }
        // A move that arrived inside the 50 ms window is picked up now.
        if let point = pendingPoint {
            processMovement(to: point, at: ProcessInfo.processInfo.systemUptime)
        }
        switch settle.fired(state: state, now: ProcessInfo.processInfo.systemUptime,
                            delayMilliseconds: preferences.delayMilliseconds) {
        case .idle:
            break
        case .rearm(let wait):
            scheduleSettleTimer(after: wait)
        case .evaluate:
            if evaluateIfSettled(delayMilliseconds: preferences.delayMilliseconds) {
                scheduleSettleTimer(after: settle.retry())
            }
        }
    }

    private func finishEvaluation(_ evaluation: FocusFollowsMouseEvaluation, succeeded: Bool) {
        state.finishEvaluation(evaluation, succeeded: succeeded)
        armSettleTimerIfNeeded()
    }

    private func resetMovement() {
        state.reset()
        timer?.invalidate()
        timer = nil
        settle.reset()
        pendingPoint = nil
    }

    /// Nothing held down: no mouse button pressed and no modifier. Asked
    /// again when the window query answers, because the query takes long
    /// enough for a click or a shortcut to begin while it runs, and a pointer
    /// that never moved keeps the answer looking current.
    private var nothingIsHeldDown: Bool {
        NSEvent.pressedMouseButtons == 0
            && NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    /// True when a button or a key is held and the look must be retried shortly.
    private func evaluateIfSettled(delayMilliseconds: Int) -> Bool {
        // No Accessibility grant: nothing to do until the next move arms the timer again.
        guard AXIsProcessTrusted() else { return false }
        guard nothingIsHeldDown else { return state.hasPendingEvaluation }
        guard let evaluation = state.nextEvaluation(
                  at: ProcessInfo.processInfo.systemUptime,
                  delayMilliseconds: delayMilliseconds)
        else { return false }
        if MouseAppExceptions.shared.excludesPointerTarget(
            .focusFollowsMouse, at: evaluation.point) {
            finishEvaluation(evaluation, succeeded: true)
            return false
        }
        guard let pointerWindowID = Self.receivingWindow(at: evaluation.point) else {
            finishEvaluation(evaluation, succeeded: false)
            return false
        }

        // WindowServer cannot report ignoresMouseEvents. Read our windows on
        // main so full-screen brightness overlays do not block focus everywhere.
        let clickThroughWindowIDs = Set(NSApp.windows.filter(\.ignoresMouseEvents).compactMap {
            CGWindowID(exactly: $0.windowNumber)
        })
        queryQueue.async { [weak self] in
            guard let self else { return }
            let target = FocusFollowsMouseSupport.queryWindow(
                in: WindowServerSupport.onScreenWindowInfo(), at: evaluation.point,
                pointerWindowID: pointerWindowID,
                ownProcessID: ProcessInfo.processInfo.processIdentifier,
                clickThroughWindowIDs: clickThroughWindowIDs
            ) { self.target(at: evaluation.point, processID: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let target else {
                    self.finishEvaluation(evaluation, succeeded: false)
                    return
                }
                let targetAppIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == target.processID
                let isCurrent = { [weak self] in
                    guard let self else { return false }
                    return self.isRunning && self.nothingIsHeldDown
                        && self.state.isCurrent(evaluation)
                        && Self.receivingWindow(at: evaluation.point) == pointerWindowID
                }
                guard isCurrent(),
                      let app = NSRunningApplication(processIdentifier: target.processID),
                      app.activationPolicy == .regular, !app.isTerminated
                else {
                    self.finishEvaluation(evaluation, succeeded: false)
                    return
                }
                guard FocusFollowsMouseSupport.shouldActivate(
                    targetWindowID: target.windowID,
                    focusedWindowID: target.focusedWindowID,
                    focusedWindowBlocksTarget: target.focusedWindowBlocksTarget,
                    focusedWindowSharesRoot: target.focusedWindowSharesRoot,
                    targetAppIsFrontmost: targetAppIsFrontmost) else {
                    self.finishEvaluation(evaluation, succeeded: true)
                    return
                }
                // The window server reports a desktop switch only once
                // its animation ends, so a target it still parks on a
                // hidden Space is a switch in flight: the activator would
                // travel there and macOS replays the slide. Hover never
                // travels between desktops.
                guard !SpaceWindowBridge.isParkedOnHiddenSpace(target.windowID) else {
                    self.finishEvaluation(evaluation, succeeded: false)
                    return
                }
                guard PortHost.defaults.bool(forKey: DefaultsKey.focusFollowsMouseRaise) else {
                    let activation = WindowActivator.supersedePendingActivations(for: target.processID)
                    SpaceWindowBridge.focusWithoutRaise(
                        target.windowID, ownerPID: target.processID,
                        replacing: targetAppIsFrontmost ? target.focusedWindowID : nil,
                        while: { isCurrent() && WindowActivator.isCurrentActivation(activation) },
                        completion: { [weak self] succeeded in
                            self?.finishEvaluation(evaluation, succeeded: succeeded)
                        })
                    return
                }
                WindowActivator.activate(pid: target.processID,
                                         windowID: target.windowID,
                                         appName: app.localizedName ?? "",
                                         retry: false)
                self.finishEvaluation(evaluation, succeeded: true)
            }
        }
        return false
    }

    /// AppKit resolves the window that would receive a click, skipping
    /// input-transparent overlays. Keep this on the main thread; the worker
    /// receives just the ID and never needs a system-wide Accessibility query.
    static func receivingWindow(at axPoint: CGPoint) -> CGWindowID? {
        WindowServerSupport.receivingWindow(at: axPoint)
    }

    private func target(at point: CGPoint, processID: pid_t) -> Target? {
        guard processID > 0, processID != ProcessInfo.processInfo.processIdentifier else { return nil }
        // An app-scoped hit test cannot enter our tree if window stacking
        // changes after the ownership lookup. Never fall back to a global query.
        let application = AXUIElementCreateApplication(processID)
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &rawElement) == .success,
              let rawElement
        else { return nil }
        AXUIElementSetMessagingTimeout(rawElement, 0.25)
        guard let window = topLevelWindow(from: rawElement) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.25)
        var windowProcessID: pid_t = 0
        guard AXUIElementGetPid(window, &windowProcessID) == .success,
              windowProcessID == processID,
              stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String),
              let windowID = AXWindowResolver.windowID(for: window)
        else { return nil }

        let focusedWindowID = WindowActivator.focusedWindowID(for: processID)
        return Target(processID: processID,
                      windowID: windowID,
                      focusedWindowID: focusedWindowID,
                      focusedWindowBlocksTarget: focusedWindowID != nil && focusedWindowID != windowID
                          && focusedWindowBlocks(windowID, in: application),
                      focusedWindowSharesRoot: focusedWindowID.map {
                          $0 != windowID && Self.rootWindowID(of: $0) == Self.rootWindowID(of: windowID)
                      } ?? false)
    }

    /// Accessibility reports a child window as a window of its own, so the
    /// window server names the window it is attached to.
    private static func rootWindowID(of windowID: CGWindowID) -> CGWindowID {
        FocusFollowsMouseSupport.rootWindowID(of: windowID,
                                              parentWindowID: SpaceWindowBridge.parentWindowID(of:))
    }

    /// A sheet holds focus for the window it is attached to, and an app-modal
    /// window for every window of its app. Accessibility hit tests land on
    /// the window behind the sheet, so the two look like different windows.
    private func focusedWindowBlocks(_ windowID: CGWindowID, in application: AXUIElement) -> Bool {
        guard var element = elementAttribute(application, kAXFocusedWindowAttribute as String) else { return false }
        AXUIElementSetMessagingTimeout(element, 0.25)
        // A confirmation can sit on top of a sheet, so walk up to the window.
        for _ in 0..<4 {
            guard stringAttribute(element, kAXRoleAttribute as String) == (kAXSheetRole as String) else { break }
            guard let parent = elementAttribute(element, kAXParentAttribute as String) else { return false }
            AXUIElementSetMessagingTimeout(parent, 0.25)
            if AXWindowResolver.windowID(for: parent) == windowID { return true }
            element = parent
        }
        // Sheets have no AXModal. The window they hang from does, so a sheet
        // on an app-modal dialog still blocks every other window of the app.
        var modal: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXModalAttribute as CFString, &modal) == .success
            && modal as? Bool == true
    }

    private func topLevelWindow(from element: AXUIElement) -> AXUIElement? {
        if stringAttribute(element, kAXRoleAttribute as String) == (kAXWindowRole as String) {
            return element
        }
        return elementAttribute(element, kAXWindowAttribute as String)
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func savedDelay() -> Int {
        FocusFollowsMouseSupport.sanitizedDelay(
            PortHost.defaults.integer(forKey: DefaultsKey.focusFollowsMouseDelay))
    }

    private struct Target {
        let processID: pid_t
        let windowID: CGWindowID
        let focusedWindowID: CGWindowID?
        let focusedWindowBlocksTarget: Bool
        let focusedWindowSharesRoot: Bool
    }
}
