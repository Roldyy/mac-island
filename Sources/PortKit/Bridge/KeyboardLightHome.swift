// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Foundation

/// The keyboard backlight for the island Home slider: a public door over the ported CoreBrightness bridge (its
/// capability probe lives in `BrightnessService`; this file loads no private symbol). Both calls answer without
/// building the brightness service. A Mac with no controllable built-in backlight reads nil and refuses writes.
public enum PortKeyboardLight {
    /// 0...1, or nil when there is no controllable keyboard backlight. Never writes.
    public static func level() -> Double? {
        BrightnessService.keyboardLightHomeLevel().map(Double.init)
    }

    /// Sets the level; clamped and finite-checked before it reaches the private setter.
    public static func setLevel(_ level: Double) -> Bool {
        guard level.isFinite else { return false }
        return BrightnessService.setKeyboardLightHomeLevel(Float(level))
    }
}
