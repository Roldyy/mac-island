// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Keeps the app's own global shortcuts quiet while the user is recording a
/// new one. Without this, typing a combination the app already answers to
/// fires that feature instead of landing in the field, so the one shortcut a
/// user most wants to change is the one they cannot type.
///
/// The state is a plain flag rather than a counter on purpose. Two fields can
/// never listen at once (only one view holds the keyboard), and if the two
/// ever disagreed, the safe outcome is shortcuts coming back on early, never
/// shortcuts left dead. `end` is therefore idempotent and every exit from
/// recording calls it: a capture, Escape, losing focus, the window closing,
/// the view going away and the app losing front.
enum ShortcutCapture {
    private(set) static var isCapturing = false

    /// Releases every global key the app holds. Main thread only, like the
    /// services it drives.
    /// Mac Island: only a feature a lane BOUND (the registry's verdict decides whether it runs) is touched, here
    /// and in `end()`. A feature nobody bound has no running service and must not get one from a recording:
    /// `FeatureRuntime.sync` starts whatever its stored switch says, and our own modules (keep awake, clipboard,
    /// shelf, command bar) hold their own hotkeys, which the recording tap already shields from the keys typed.
    static func begin() {
        guard !isCapturing else { return }
        isCapturing = true
        // A flag inside the routing, not a teardown: rebuilding the tap per
        // recording would churn the system keyboard path (issue #275).
        if PortShortcutOwnership.isBound(.switcher) { AppSwitcher.shared.setCapturingShortcut(true) }
        if PortShortcutOwnership.upstreamKeepAwakeHotkeyAllowed { HotkeyManager.shared.setEnabled(false) }
        if PortShortcutOwnership.isBound(.shelf) { ShelfService.shared.suspendShortcut() }
        if PortShortcutOwnership.isBound(.clipboardHistory) { ClipboardHistoryService.shared.suspendShortcut() }
        if PortShortcutOwnership.isBound(.soundOutputSwitcher) { SoundOutputSwitcher.shared.suspendShortcut() }
        if PortShortcutOwnership.isBound(.windowLayout) { WindowLayoutService.shared.suspendShortcuts() }
        QuickToolHotkey.unregisterAll()
    }

    /// Gives every key back. Safe to call when nothing was suspended, and safe
    /// to call twice; the features re-read their own preferences, so a feature
    /// switched off in the meantime simply stays off.
    static func end() {
        guard isCapturing else { return }
        isCapturing = false
        if PortShortcutOwnership.isBound(.switcher) { AppSwitcher.shared.setCapturingShortcut(false) }
        FeatureRuntime.shared.sync(GlobalShortcutRole.featuresToSilenceWhileRecording.filter(PortShortcutOwnership.isBound))
    }
}
