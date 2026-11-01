// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit

/// A Space of the island's own, shown over the desktops at the default level.
/// A stationary window stays put when the desktop is revealed, but it belongs
/// to the desktops, so a swipe between desktops or into a full-screen app
/// slides it away with the wallpaper and back. A window that joins this Space
/// before it is first shown belongs to no desktop at all, so no desktop change
/// moves it, like the menu bar. Windows still order by their own level
/// against every other window: native menus and dialogs stay above the island.
///
/// AppKit then never counts the window as on the active Space; key focus,
/// tracking and the display link work as before. Its only Space must never
/// be destroyed under it, or the window would have none and never show
/// again. Without the symbols the island keeps sliding with the desktop, as before.
///
/// Given an absolute level, the Space is drawn with the system's own layers
/// instead: at the level of its lock screen notifications, over the lock
/// screen itself.
///
/// Mac Island: the private WindowServer symbols are not resolved here any more. They live in `PrivateOverlaySpace.swift`
/// behind `OverlaySpaceProviding`, with a capability probe, a kill switch and a journal written before the first call.
final class NotchOverlaySpace {
    private let backend: OverlaySpaceBackend

    init?(absoluteLevel: Int32? = nil) {
        guard let backend = PrivateOverlaySpace.provider.makeSpace(absoluteLevel: absoluteLevel) else { return nil }
        self.backend = backend
    }

    deinit { close() }

    /// Joins a window before it is first ordered in: one already on screen
    /// would stay on its desktop as well and still slide with it. Ordering
    /// out and in again keeps the window here.
    func add(_ window: NSWindow) {
        backend.add(windowNumber: window.windowNumber)
    }

    /// Windows leave before the Space goes: a window whose only Space is
    /// destroyed would belong to none and never show again.
    func close() {
        backend.close()
    }
}
