// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct MonitorLayoutFeatureStrings {
    /// Heading for the settings shared by the menu bar and the panel.
    let shared: String
    /// Names the bytes or bits choice for live network speeds, as its
    /// settings row and as the panel button that flips it.
    let networkSpeedUnit: String
}

extension FeatureStrings {
    static func monitorLayout(_ language: AppLanguage) -> MonitorLayoutFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension MonitorLayoutFeatureStrings {
    static let enUS = MonitorLayoutFeatureStrings(
        shared: "Readings and alerts",
        networkSpeedUnit: "Network speed unit"
    )

    static let fr = MonitorLayoutFeatureStrings(
        shared: "Mesures et alertes",
        networkSpeedUnit: "Unité de débit réseau"
    )

}
