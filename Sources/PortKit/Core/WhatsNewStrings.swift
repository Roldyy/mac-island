// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct WhatsNewStrings {
    /// The %@ is the version the person updated from, such as 3.4.1.
    let updatedFromFormat: String
    let newFeatures: String
    /// Installed features that changed in this update.
    let yourFeatures: String
    let notInstalled: String
    /// The three kinds head a feature's list of changes and label the counts on
    /// the overview, so they must read well both above a list and under a number.
    let kindNew: String
    let kindChanged: String
    let kindFixed: String
    /// VoiceOver value for a sidebar row whose unread dot is showing.
    let updated: String
    let chooseFeatureHint: String
    /// Checkbox in the pre-install window footer, beside Cancel and Download and install.
    let skipPreviewCheckbox: String
    let showPreviewToggle: String
    let showPreviewCaption: String
}

extension FeatureStrings {
    static func whatsNew(_ language: AppLanguage) -> WhatsNewStrings {
        switch language {
        case .enUS:
            return WhatsNewStrings(
                updatedFromFormat: "Updated from %@",
                newFeatures: "New features",
                yourFeatures: "Your features",
                notInstalled: "Not installed",
                kindNew: "New",
                kindChanged: "Changed",
                kindFixed: "Fixed",
                updated: "Updated",
                chooseFeatureHint: "Choose a feature to see what changed in it.",
                skipPreviewCheckbox: "Don’t show what’s new before updating",
                showPreviewToggle: "Show what’s new before updating",
                showPreviewCaption: "What changed in your features still appears after each update.")
        default:
            return WhatsNewStrings(
                updatedFromFormat: "Mis à jour depuis la version %@",
                newFeatures: "Nouvelles fonctions",
                yourFeatures: "Vos fonctions",
                notInstalled: "Non installées",
                kindNew: "Nouveautés",
                kindChanged: "Modifications",
                kindFixed: "Corrections",
                updated: "Mise à jour",
                chooseFeatureHint: "Choisissez une fonction pour voir ce qui a changé.",
                skipPreviewCheckbox: "Masquer les nouveautés avant la mise à jour",
                showPreviewToggle: "Afficher les nouveautés avant la mise à jour",
                showPreviewCaption: "Ce qui a changé dans vos fonctions s’affiche toujours après chaque mise à jour.")
        }
    }
}
