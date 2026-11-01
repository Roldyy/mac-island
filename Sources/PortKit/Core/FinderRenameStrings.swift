// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct FinderRenameFeatureStrings {
    let pageTitle: String
    let hubTitle: String
    let hubDescription: String
    let enableLabel: String
    let caption: String
    let shortcutLabel: String
}

extension FeatureStrings {
    static func finderRename(_ language: AppLanguage) -> FinderRenameFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension FinderRenameFeatureStrings {
    static let enUS = FinderRenameFeatureStrings(
        pageTitle: "Finder shortcuts",
        hubTitle: "Rename shortcut",
        hubDescription: "Rename the selected file or folder with a shortcut you choose.",
        enableLabel: "Use a shortcut to rename",
        caption: "The shortcut only acts in Finder and leaves text fields alone. F2 works as a regular key; on keyboards where it controls brightness, use Fn-F2 or choose another shortcut.",
        shortcutLabel: "Rename"
    )

    static let fr = FinderRenameFeatureStrings(
        pageTitle: "Raccourcis du Finder",
        hubTitle: "Raccourci pour renommer",
        hubDescription: "Renommez le fichier ou le dossier sélectionné avec le raccourci de votre choix.",
        enableLabel: "Utiliser un raccourci pour renommer",
        caption: "Le raccourci agit uniquement dans le Finder et laisse les champs de texte intacts. F2 fonctionne comme une touche normale\u{00A0}; si elle règle la luminosité, utilisez Fn-F2 ou choisissez un autre raccourci.",
        shortcutLabel: "Renommer"
    )

}
