// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct ShortcutSettingsStrings {
    let active: String
    let inactive: String
    let superKeyAlternativeFormat: String
}

extension FeatureStrings {
    static func shortcuts(_ language: AppLanguage) -> ShortcutSettingsStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension ShortcutSettingsStrings {
    static let enUS = ShortcutSettingsStrings(
        active: "Active",
        inactive: "Inactive",
        superKeyAlternativeFormat: "or %@"
    )

    static let fr = ShortcutSettingsStrings(
        active: "Actif",
        inactive: "Inactif",
        superKeyAlternativeFormat: "ou %@"
    )

}
