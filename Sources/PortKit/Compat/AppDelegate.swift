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

    func openSettingsWindow() { openSettings?() }

    func closePopover(animated: Bool = true, after delay: TimeInterval = 0, preservingNotch: Bool = false,
                      reason: PanelCloseReason = .action, completion: (() -> Void)? = nil) {
        closePanel?()
        completion?()
    }

    func isOverStatusItem(_ point: NSPoint) -> Bool { isOverMenuBarItem?(point) ?? false }

    func relaunchApp() { relaunch?() }

    // Feedback, onboarding, update tour: none of them exists in Mac Island.
    func openFeedbackWindow(kind: FeedbackKind = .bug) {}
    func showUpdatePreview() {}
    func showUpdateHighlights(isReview: Bool = false) {}
    func openSettingsFromHighlights() { openSettingsWindow() }
    func showOnboarding(mode: OnboardingMode = .full) {}
    func reshowStatusItem() {}
}

enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case feature
}

enum OnboardingMode {
    case full
}
