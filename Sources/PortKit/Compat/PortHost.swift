// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.
//
// The only switches between the ported Vorssaint code and Mac Island. Everything here is inert by default:
// importing PortKit starts no feature, opens no window and asks for no permission.

import Foundation

public enum PortHost {
    /// Vorssaint's own island window. Mac Island has its own island, so this stays off until a bridge lane
    /// decides to let the ported one run (it never should while ours is on screen).
    /// Read by `NotchService.syncWithPreferences()` and `AppFeature.notch`.
    public nonisolated(unsafe) static var vorssaintIslandEnabled = false

    /// Mac Island's own island is the app: it is always on, so every ported page that asked "is the Dynamic Island installed
    /// and on?" (the Companion's "activate Dynamic Island" card) must answer yes. Read by `CompanionSwitch`.
    public static let hostsOwnIsland = true

    /// Mac Island's `FeatureRegistry` is the only writer of `shell.enabled.<id>`. When a bridge lane sets this,
    /// the ported `FeatureRuntime.setAvailable` hands the switch over instead of writing the key itself.
    public nonisolated(unsafe) static var setEnabled: (@Sendable (_ featureID: String, _ enabled: Bool) -> Void)?

    /// Language of the ported interface. Always French: `L10n` ignores every other value.
    public static let language = "fr"

    /// Folder of the ported data files, under the app's own Application Support folder.
    public static let dataFolderName = "Data"

    /// Bundle identifier of Mac Island. Fixed on purpose: `swift test` has a different `Bundle.main`.
    public static let bundleID = "be.roldy.macisland"
}
