// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Foundation

/// The list of every door the ported code leaves open for the host (`Compat/*.swift`, `PortHostState.swift`, the
/// `requestPermission` doors of the Dock and capture lanes, the island gestures) and what became of it.
/// A hook is either BOUND by the app (through the text named in `door`, found in `MacIsland/AppDelegate.swift`) or ALLOWED
/// to stay unbound or empty, with the reason. `PortHookTests` scans those sources against this list, so a new hook, or a new
/// do-nothing stub, that is in neither fails the tests: no more buttons that silently do nothing.
enum PortHookCatalog {
    struct Bound {
        let name: String
        /// The text that binds it in the app delegate (a `PortBridge.Host` label, or an entry point).
        let door: String
        /// True when the app may legitimately leave it nil (no relaunch action outside a bundle).
        let optional: Bool
        /// True for the hooks of the `AppDelegate` facade: `PortBridge.unboundHooks` reports those.
        let onFacade: Bool
    }

    static let bound: [Bound] = [
        Bound(name: "openSettings", door: "openSettings:", optional: false, onFacade: true),
        Bound(name: "closePanel", door: "closePanel:", optional: false, onFacade: true),
        Bound(name: "relaunch", door: "relaunch:", optional: true, onFacade: true),
        Bound(name: "openSettingsPage", door: "openSettingsPage:", optional: false, onFacade: true),
        Bound(name: "openFeedback", door: "openFeedback:", optional: false, onFacade: true),
        Bound(name: "openIslandTab", door: "PortBridge.connectIsland", optional: false, onFacade: true),
        Bound(name: "closeIsland", door: "PortBridge.connectIsland", optional: false, onFacade: true),
        Bound(name: "reshowIcon", door: "PortBridge.connectMenuBar", optional: false, onFacade: true),
        Bound(name: "setEnabled", door: "PortBridge.connectRegistry", optional: false, onFacade: false),
        Bound(name: "storedSwitch", door: "PortBridge.connectRegistry", optional: false, onFacade: false),
        Bound(name: "availability", door: "PortBridge.bindLanes", optional: false, onFacade: false),
        Bound(name: "requestPermission", door: "requestPermission", optional: false, onFacade: false),
        Bound(name: "clipboardIsOn", door: "PortDockCommands.clipboardIsOn", optional: false, onFacade: false),
        Bound(name: "clearClipboardUnpinned", door: "PortDockCommands.clearClipboardUnpinned", optional: false, onFacade: false),
        Bound(name: "pastePlainFromClipboard", door: "PortDockCommands.pastePlainFromClipboard", optional: false, onFacade: false),
        Bound(name: "context", door: "PortIslandGestureHost.install", optional: false, onFacade: false),
        Bound(name: "perform", door: "PortIslandGestureHost.install", optional: false, onFacade: false),
    ]

    /// Hooks and stubs that stay unbound or empty on purpose. The key is the member name in the scanned sources.
    static let allowlist: [String: String] = [
        "isOverMenuBarItem": "read only by NotchService, which stays asleep (PortHost.vorssaintIslandEnabled is false); our island has its own hover rules",
        "showUpdatePreview": "update banner of the ported panel: UpdateService never leaves .idle here, so no button reaches it; updates are ShellKit's UpdateChecker",
        "showUpdateHighlights": "the upstream update tour: only SettingsView (not hosted) calls it; Mac Island has its own Nouveautes page",
        "showOnboarding": "the upstream first-run tour: only SettingsView (not hosted) calls it",
        "checkIfStale": "UpdateService is a read-only stand-in (state stays .idle): updates are ShellKit's UpdateChecker",
        "check": "UpdateService is a read-only stand-in (state stays .idle): updates are ShellKit's UpdateChecker",
        "refresh": "the share services have no server (isAvailable is false): every screen that lists links is hidden",
        "save": "AgentPriceSource has no network: the bundled price list is the only source",
    ]

    /// Whether the facade holds the hook of that name.
    static func isBound(_ name: String, on facade: AppDelegate?) -> Bool {
        guard let facade else { return false }
        switch name {
        case "openSettings": return facade.openSettings != nil
        case "closePanel": return facade.closePanel != nil
        case "relaunch": return facade.relaunch != nil
        case "openSettingsPage": return facade.openSettingsPage != nil
        case "openFeedback": return facade.openFeedback != nil
        case "openIslandTab": return facade.openIslandTab != nil
        case "closeIsland": return facade.closeIsland != nil
        case "reshowIcon": return facade.reshowIcon != nil
        default: return false
        }
    }
}
