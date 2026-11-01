// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct BatteryTimeFeatureStrings {
    let title: String
    let systemEstimate: String
    let calculating: String
}

extension FeatureStrings {
    static func batteryTime(_ language: AppLanguage) -> BatteryTimeFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension BatteryTimeFeatureStrings {
    static let enUS = BatteryTimeFeatureStrings(
        title: "Battery time remaining",
        systemEstimate: "System estimate",
        calculating: "Calculating…"
    )

    static let fr = BatteryTimeFeatureStrings(
        title: "Autonomie restante",
        systemEstimate: "Estimation du système",
        calculating: "Calcul…"
    )

}
