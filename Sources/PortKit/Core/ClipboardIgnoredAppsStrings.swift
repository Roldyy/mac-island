// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct ClipboardIgnoredAppsStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func clipboardIgnoredApps(_ language: AppLanguage) -> ClipboardIgnoredAppsStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension ClipboardIgnoredAppsStrings {
    static let enUS = ClipboardIgnoredAppsStrings(
        listTitle: "Apps to skip",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "Nothing you copy in these apps is saved to the history."
    )

    static let fr = ClipboardIgnoredAppsStrings(
        listTitle: "Apps à ignorer",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        caption: "Rien de ce que vous copiez dans ces apps n’est gardé dans l’historique."
    )

}
