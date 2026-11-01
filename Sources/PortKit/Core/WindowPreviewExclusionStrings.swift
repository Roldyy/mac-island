// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct WindowPreviewExclusionStrings {
    let sectionTitle: String
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowPreviewExclusions(_ language: AppLanguage) -> WindowPreviewExclusionStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension WindowPreviewExclusionStrings {
    static let enUS = WindowPreviewExclusionStrings(
        sectionTitle: "Window thumbnails",
        listTitle: "Pause in these apps",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "Window thumbnails stop while one of these apps is in front."
    )

    static let fr = WindowPreviewExclusionStrings(
        sectionTitle: "Aperçus des fenêtres",
        listTitle: "Mettre en pause dans ces apps",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        caption: "Les aperçus des fenêtres s’arrêtent tant que l’une de ces apps est au premier plan."
    )

}
