// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct AppearanceStrings {
    let label: String
    let system: String
    let light: String
    let dark: String
    let liquidGlass: String
}

extension FeatureStrings {
    static func appearance(_ language: AppLanguage) -> AppearanceStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension AppearanceStrings {
    static let enUS = AppearanceStrings(
        label: "Appearance",
        system: "System",
        light: "Light",
        dark: "Dark",
        liquidGlass: "Liquid Glass"
    )

    static let fr = AppearanceStrings(
        label: "Apparence",
        system: "Système",
        light: "Clair",
        dark: "Sombre",
        liquidGlass: "Liquid Glass"
    )

}
