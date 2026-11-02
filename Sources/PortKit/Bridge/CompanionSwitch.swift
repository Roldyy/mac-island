// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Foundation

/// The Compagnon has two upstream switches: the registry's (`shell.enabled.notchMascot`, the Fonctionnalites row) and
/// upstream's own `notchMascotEnabled`, the toggle of its page. Both used to be shown and driven separately, so the page
/// toggle could read off while the feature ran. One source of truth now: the companion is ON when both say on, and
/// the page toggle sets both together. A start of the feature (the Fonctionnalites switch) writes the page key ON too
/// (`IslandLockScreenLane.Runtime.mascotStart`).
enum CompanionSwitch {
    static let featureID = "notchMascot"

    static func isOn(in defaults: UserDefaults = PortHost.defaults) -> Bool {
        AppFeature.notchMascot.isAvailable(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotEnabled)
    }

    /// The page toggle. The key first, so the feature's start (and its seed) finds it set; then the registry's switch.
    static func set(_ on: Bool, in defaults: UserDefaults = PortHost.defaults,
                    setFeature: ((String, Bool) -> Void)? = PortHost.setEnabled) {
        defaults.set(on, forKey: DefaultsKey.notchMascotEnabled)
        setFeature?(featureID, on)
    }

    /// Whether the page may skip the "activate Dynamic Island" card: Mac Island's island is always on.
    static func islandIsOn(installed: Bool, enabled: Bool, hostsOwnIsland: Bool = PortHost.hostsOwnIsland) -> Bool {
        hostsOwnIsland || (installed && enabled)
    }
}
