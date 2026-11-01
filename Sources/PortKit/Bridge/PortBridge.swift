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

    /// Connects the ported code to the host. Idempotent.
    public static func install(host: Host) {
        let facade = AppDelegate()
        facade.openSettings = host.openSettings
        facade.closePanel = host.closePanel
        facade.relaunch = host.relaunch
        facade.isOverMenuBarItem = host.isOverMenuBarItem
        AppDelegate.current = facade
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
