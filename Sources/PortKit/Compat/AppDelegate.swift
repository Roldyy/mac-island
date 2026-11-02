// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit

/// Stand-in for Vorssaint's app delegate. The ported code only ever asks it to close a panel, open Settings
/// or report where the menu bar item is; Mac Island's own delegate fills the closures at launch through
/// `PortBridge`. Every closure is nil until then, so each call is a no-op.
final class AppDelegate {
    static var current: AppDelegate?

    var openSettings: (() -> Void)?
    var closePanel: (() -> Void)?
    var relaunch: (() -> Void)?
    var isOverMenuBarItem: ((NSPoint) -> Bool)?
    /// Mac Island's own doors (`PortBridge.install` / `connectIsland` / `connectMenuBar`). Every optional hook of this class
    /// is either bound by the app or listed with a reason in `PortHookCatalog` (a test enforces it).
    var openSettingsPage: ((String) -> Void)?
    var openIslandTab: ((String) -> Void)?
    var closeIsland: (() -> Void)?
    var openFeedback: ((FeedbackKind) -> Void)?
    var reshowIcon: (() -> Void)?

    func openSettingsWindow() { openSettings?() }

    func closePopover(animated: Bool = true, after delay: TimeInterval = 0, preservingNotch: Bool = false,
                      reason: PanelCloseReason = .action, completion: (() -> Void)? = nil) {
        closePanel?()
        completion?()
    }

    func isOverStatusItem(_ point: NSPoint) -> Bool { isOverMenuBarItem?(point) ?? false }

    func relaunchApp() { relaunch?() }

    /// Opens Mac Island's own Settings on the page whose catalog id is `id` (`PortSettingsNavigation` maps upstream's pages).
    func openSettingsPage(id: String) {
        if let openSettingsPage { openSettingsPage(id) } else { openSettingsWindow() }
    }

    /// Opens the island on the tab `id` (a feature tab id of ShellKit).
    func openIslandTab(id: String) { openIslandTab?(id) }

    /// "Report a bug" / "suggest a feature": the project's issue form (no in-app feedback window in Mac Island).
    func openFeedbackWindow(kind: FeedbackKind = .bug) { openFeedback?(kind) }

    /// "Show the menu bar icon": the app's own icon, which the metrics may have hidden.
    func reshowStatusItem() { reshowIcon?() }

    // Onboarding and update tour: none of them exists in Mac Island (the update state never leaves `idle`).
    func showUpdatePreview() {}
    func showUpdateHighlights(isReview: Bool = false) {}
    func openSettingsFromHighlights() { openSettingsWindow() }
    func showOnboarding(mode: OnboardingMode = .full) {}
}

enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case feature
}

enum OnboardingMode {
    case full
}
