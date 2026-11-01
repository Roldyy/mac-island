// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct SwitcherAppRulesStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let behaviorLabel: String
    let showWithoutWindows: String
    let windowsOnly: String
    let hidden: String
    let caption: String
}

extension FeatureStrings {
    static func switcherAppRules(_ language: AppLanguage) -> SwitcherAppRulesStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension SwitcherAppRulesStrings {
    static let enUS = SwitcherAppRulesStrings(
        listTitle: "Rules by app",
        addButton: "Add an app…",
        removeButton: "Remove",
        behaviorLabel: "Switcher behavior",
        showWithoutWindows: "Show without windows",
        windowsOnly: "Windows only",
        hidden: "Never show",
        caption: "Choose how each app appears. Apps without a rule use the choice above."
    )

    static let fr = SwitcherAppRulesStrings(
        listTitle: "Règles par app",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        behaviorLabel: "Comportement dans le sélecteur",
        showWithoutWindows: "Afficher sans fenêtre",
        windowsOnly: "Avec fenêtres uniquement",
        hidden: "Ne jamais afficher",
        caption: "Choisissez comment chaque app apparaît. Sans règle, l’app utilise le choix ci-dessus."
    )

}
