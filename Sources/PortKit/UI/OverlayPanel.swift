// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import IslandKit

/// A panel that floats over other apps' windows, such as the Shelf. AppKit
/// describes a non-activating panel as a system dialog, which tiling window
/// managers then track and list on whichever space is current; the borderless
/// overlays they leave alone are undescribed windows. It stays an accessible
/// window for assistive technology.
class OverlayPanel: NSPanel {
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }

    // Mac Island: an accessory app has no Edit menu and a non-activating panel never activates it, so Cmd+C / X / V / A / Z
    // reached no text field in here. What no view answered goes to the focused text input.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return EditKeyRouting.handle(event, in: self)
    }
}
