// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W3D (auto-quit and Spaces). The lane owns this file.

import AppKit
import Foundation
import SwiftUI

/// Binds this lane's ported features. Called once at launch by `PortLanes`, before the registry exists.
///
/// - `autoQuit`: two halves under one switch. (1) The upstream `AutoQuitService`: an app is asked to quit when its
///   last window closes (Accessibility observers, a listen-only click and key monitor to tell a close from a
///   tab). (2) The inactivity half (`AutoQuitIdleMonitor`, the logic of Mac Island's former Display module): an
///   app with no window for a set time is announced, then asked to quit, in simulation until the person says
///   otherwise. Both end an app only with the polite `terminate()` (the app may show "Save changes?"), both
///   obey `AutoQuitSafety` (never Finder, Mac Island, an app that plays sound or shows a Save panel or alert,
///   the never-quit list; the inactivity half never the app in front) and share that one list.
///   Start is each half's `sync` (it reads its page toggle and the registry's verdict); stop is a force-stop.
/// - `spacesOrder`: upstream `SpacesOrderHold` turns off the Dock's "rearrange Spaces by recent use" and puts the
///   person's setting back. It writes `com.apple.dock mru-spaces` and restarts the Dock, so it acts ONLY once the
///   registry switch AND the page toggle are on (never at launch without them), restarts the Dock only through
///   `SpacesDockRestartGuard` and only when the preference really changed, and gives the setting back on stop
///   (kill switch, safe mode, switch off), on quit (`willTerminate`) and after a crash (the journal in
///   `spacesOrderRestore` / `spacesOrderRestartPending`, settled by `SpacesOrderHold.recoverIfNeeded`, called
///   from `PortBridge.recoverAtLaunch`).
///
/// Two pages: `quitonclose` (31) for `autoQuit`, `spaces` (34) for `spacesOrder`. Nothing here prompts.
enum AutoQuitSpacesLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        var syncAutoQuit: @MainActor () -> Void
        var stopAutoQuit: @MainActor () -> Void
        var syncSpaces: @MainActor () -> Void
        /// Gives the Dock setting back, now. Entered only when something is owed.
        var stopSpaces: @MainActor () -> Void
        /// Same, synchronously, before the process goes.
        var restoreBeforeTermination: @MainActor () -> Void

        /// Services are only built once a start reached them: a Mac where the features stay off builds nothing.
        @MainActor private static var autoQuitTouched = false

        static let live = Runtime(
            syncAutoQuit: {
                autoQuitTouched = true
                AutoQuitService.shared.syncWithPreferences()
                AutoQuitIdleMonitor.shared.sync()
            },
            stopAutoQuit: {
                guard autoQuitTouched else { return }
                AutoQuitService.shared.suspend()
                AutoQuitIdleMonitor.shared.stop()
            },
            syncSpaces: { SpacesOrderHold.shared.syncWithPreferences() },
            stopSpaces: { restoreSpacesIfOwed() },
            restoreBeforeTermination: { restoreSpacesIfOwed() })

        /// `restoreForRemoval` waits for the change; it is entered only when a marker or an owed restart exists, so
        /// a Mac where the hold never ran builds no hold and touches no Dock.
        @MainActor private static func restoreSpacesIfOwed() {
            guard SpacesOrderHold.hasPendingRestore else { return }
            _ = SpacesOrderHold.restoreForRemoval()
        }
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installTerminationHook(runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        AutoQuitIdleKeys.adoptLegacyExclusions(in: PortHost.defaults)
        binding.bind(.autoQuit,
                     page: PortFeaturePage(pageID: "quitonclose") { AnyView(AutoQuitPage()) },
                     start: runtime.syncAutoQuit, stop: runtime.stopAutoQuit)
        binding.bind(.spacesOrder,
                     page: PortFeaturePage(pageID: "spaces") { AnyView(SpacesOrderPage()) },
                     start: runtime.syncSpaces, stop: runtime.stopSpaces)
    }

    // MARK: Quit

    @MainActor private static var terminationObserver: NSObjectProtocol?

    /// The app delegate has no hook for this lane, so it takes its own: when the app quits normally the Dock
    /// setting this app changed is put back before the process goes. Once.
    @MainActor static func installTerminationHook(runtime: Runtime) {
        guard terminationObserver == nil else { return }
        // No queue: the notification is posted on the main thread and the restore must finish before the process
        // goes, so the block runs inline there.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { runtime.restoreBeforeTermination() }
        }
    }

    /// Takes the hook out again (tests: it is process-wide).
    @MainActor static func removeTerminationHook() {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
    }
}
