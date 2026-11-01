// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import AppKit
import SwiftUI

/// The only public surface of PortKit. Mac Island's app delegate calls `install` once at launch; each lane
/// then registers its page bodies and action overrides from its own `Bridge/<Lane>.swift`.
///
/// Calling `install` starts nothing: it only fills the closures the ported code uses to reach the host
/// (open Settings, close the panel, relaunch). No tap, timer, window or permission prompt.
@MainActor
public enum PortBridge {
    /// What the host lends to the ported code.
    public struct Host {
        public var openSettings: () -> Void
        public var closePanel: () -> Void
        public var relaunch: (() -> Void)?
        public var isOverMenuBarItem: (NSPoint) -> Bool

        public init(openSettings: @escaping () -> Void, closePanel: @escaping () -> Void = {},
                    relaunch: (() -> Void)? = nil, isOverMenuBarItem: @escaping (NSPoint) -> Bool = { _ in false }) {
            self.openSettings = openSettings
            self.closePanel = closePanel
            self.relaunch = relaunch
            self.isOverMenuBarItem = isOverMenuBarItem
        }
    }

    private static var pageBodies: [String: () -> AnyView] = [:]
    private static var actionOverrides: [String: () -> Void] = [:]

    // MARK: Foundation (called by the app delegate, in this order, before `FeatureRegistry.launch`; step 6 is the recovery)

    /// 1. The defaults object of the port: the one the registry and the migrator use (`AppDefaults.make()`).
    ///    Call before any ported service is touched.
    public static func configure(defaults: UserDefaults) {
        PortHost.defaults = defaults
    }

    /// 2. Lets every lane bind its features into `PortFeatureBinding.shared`. Once. Registry-independent:
    ///    the descriptors it yields go into the registry's init.
    public static func bindLanes() {
        guard !didBindLanes else { return }
        didBindLanes = true
        PortLanes.bindAll(into: PortFeatureBinding.shared)
        PortFeatureBinding.shared.connectAvailability()
    }

    /// 3. The two doors to `FeatureRegistry` (PortKit cannot see ShellKit): flip a switch, read what is stored.
    ///    The registry stays the only writer of `shell.enabled.<id>`.
    public static func connectRegistry(setEnabled: @escaping @Sendable (_ id: String, _ enabled: Bool) -> Void,
                                       storedSwitch: @escaping @Sendable (_ id: String) -> Bool?) {
        PortHost.setEnabled = setEnabled
        PortHost.storedSwitch = storedSwitch
    }

    /// 4. Every reading of the `PermissionMonitor`, so `Permissions.shared` and the binding's start gate follow it.
    ///    Call before the registry starts anything, then on each change.
    public static func updatePermissions(_ state: PortPermissionState) {
        if PortHost.permissionState.value != state { PortHost.permissionState.send(state) }
    }

    /// 5. Upstream's registered defaults and first-launch seeds. AFTER the Vorssaint migration (v1, v2, purge)
    ///    and the registry seed, BEFORE the registry starts any ported feature. Once. Never from `main.swift`.
    public static func registerDefaults() {
        guard !didRegisterDefaults else { return }
        didRegisterDefaults = true
        Defaults.register(in: PortHost.defaults)
    }

    private static var didBindLanes = false
    private static var didRegisterDefaults = false

    /// Connects the ported code to the host. Idempotent.
    public static func install(host: Host) {
        let facade = AppDelegate()
        facade.openSettings = host.openSettings
        facade.closePanel = host.closePanel
        facade.relaunch = host.relaunch
        facade.isOverMenuBarItem = host.isOverMenuBarItem
        AppDelegate.current = facade
        recoverAtLaunch()
    }

    // MARK: Launch

    /// The re-exec'd cleanup flags of the ported guards (`--super-key-mapping-cleanup`,
    /// `--mouse-acceleration-cleanup`). Called from `main.swift` before `NSApplication` exists: when a flag is
    /// present the process does its cleanup and exits, so no second app ever starts.
    /// (`KeepAwakeManager` has no such flag: only `recoverIfNeeded`, below.)
    public static func runCleanupFlagsIfRequested() {
        SuperKeyMappingGuard.runIfRequestedAndExit()
        MouseAccelerationGuard.runIfRequestedAndExit()
    }

    private static var didRecoverAtLaunch = false
    private(set) static var recoveryRuns = 0

    /// 6. Gives back what a run that died left applied. The app delegate calls it right after `registerDefaults`
    ///    and BEFORE `FeatureRegistry.launch`: a feature that starts first (the mouse acceleration, the gamma
    ///    dim) writes its own journal, and a recovery that ran afterwards would read that fresh journal as a
    ///    crash and undo the feature on every launch. Idempotent: the later `install` call finds it done.
    public static func recoverBeforeLaunch() { recoverAtLaunch() }

    /// Recovery first, then the closure that starts the features. The order is the point (see above); `recover`
    /// is a seam for the test that records it.
    public static func launchAfterRecovery(_ start: () -> Void) { launchAfterRecovery(recover: { recoverAtLaunch() }, start: start) }

    static func launchAfterRecovery(recover: () -> Void, start: () -> Void) {
        recover()
        start()
    }

    static var hasRecoveredAtLaunch: Bool { didRecoverAtLaunch }

    /// Test seam: makes the next `recoverAtLaunch` run again.
    static func resetRecoveryForTesting() { didRecoverAtLaunch = false; recoveryRuns = 0 }

    /// Which crash-recovery steps have something to undo. A step with no marker is never entered, so a Mac
    /// where the ported services never ran gets no daemon registration, no prompt and no `shared` singleton
    /// built. `MouseAccelerationService.recoverPendingAtLaunch` and `SpacesOrderHold.recoverIfNeeded` test
    /// their own marker (a journal file, the Spaces keys) and are called unconditionally.
    struct RecoveryPlan: Equatable {
        var keepAwake = false
        var systemShortcuts = false
        var fanControl = false

        init(defaults: UserDefaults) {
            keepAwake = defaults.bool(forKey: DefaultsKey.sleepDisabledFlag)
                || defaults.object(forKey: DefaultsKey.dimmedDisplaySavedBrightness) != nil
            systemShortcuts = defaults.object(forKey: DefaultsKey.systemShortcutsSuppressed) != nil
                || defaults.object(forKey: DefaultsKey.switcherNativeHotkeysSuppressed) != nil
            fanControl = defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
        }
    }

    /// Gives back what an earlier run of the ported services left applied (upstream ran these in `main.swift`
    /// and `applicationDidFinishLaunching`; the port had dropped them). Once per launch, only for a marker
    /// that is actually set. Nothing is started. Runs from the app delegate before the registry starts any
    /// feature (`recoverBeforeLaunch`); `install` calls it again and finds it done.
    static func recoverAtLaunch(defaults: UserDefaults = PortHost.defaults) {
        guard !didRecoverAtLaunch else { return }
        didRecoverAtLaunch = true
        recoveryRuns += 1
        let plan = RecoveryPlan(defaults: defaults)
        if plan.systemShortcuts { SystemShortcutTakeover.recoverIfNeeded(keeping: []) }
        if plan.keepAwake { KeepAwakeManager.shared.recoverIfNeeded() }
        if plan.fanControl { FanControlService.recoverIfNeeded() }
        MouseAccelerationService.recoverPendingAtLaunch()
        SpacesOrderHold.recoverIfNeeded()
        // A gamma dim or a switched-off display left by a run that died: each step tests its own marker.
        DisplayBrightnessLane.recoverAtLaunch(defaults: defaults)
        // The Dock auto-hide a "keep the Dock visible" hover left held: entered only when its journal is set.
        DockLane.recoverAtLaunch(defaults: defaults)
        // A recording a crash cut short: saved when it plays, deleted when it does not (only when its journal is set).
        RecorderLane.recoverAtLaunchLive()
    }

    // MARK: Settings page bodies

    /// A lane plugs the body of one Settings page (our page id) here.
    public static func register(pageID: String, body: @escaping () -> AnyView) { pageBodies[pageID] = body }

    /// Page ids that have a ported body, for the host to hand to ShellKit.
    public static var registeredPageIDs: [String] { pageBodies.keys.sorted() }

    /// The ported body of a page, nil when no lane registered one.
    public static func settingsBody(pageID: String) -> AnyView? { pageBodies[pageID]?() }

    // MARK: Actions

    /// A lane overrides one quick action or command by key, so nobody edits the app delegate.
    public static func register(actionKey: String, run: @escaping () -> Void) { actionOverrides[actionKey] = run }

    /// The override for a key, nil when none.
    public static func action(forKey key: String) -> (() -> Void)? { actionOverrides[key] }

    // MARK: Gate

    /// Whether Vorssaint's own island may run. Off by default: Mac Island has one island.
    public static var vorssaintIslandEnabled: Bool {
        get { PortHost.vorssaintIslandEnabled }
        set { PortHost.vorssaintIslandEnabled = newValue }
    }
}
