// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Strings for the quick toggles tab. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct QuickToggleFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let darkModeToDark: String
    let darkModeToLight: String
    let darkModeCaption: String
    let emptyTrashTitle: String
    let emptyTrashCaption: String
    let emptyTrashConfirmTitle: String
    let emptyTrashConfirmMessage: String
    let emptyTrashConfirmButton: String
    let ejectTitle: String
    let ejectCaption: String
    let hiddenFilesShow: String
    let hiddenFilesHide: String
    let desktopIconsHide: String
    let desktopIconsShow: String
    let finderRestartCaption: String
    let lockScreenTitle: String
    let lockScreenCaption: String
    let displayOffTitle: String
    let displayOffCaption: String
    let screenSaverTitle: String
    let screenSaverCaption: String
    let actionFailed: String
}

extension FeatureStrings {
    static func quickToggles(_ language: AppLanguage) -> QuickToggleFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension QuickToggleFeatureStrings {
    static let enUS = QuickToggleFeatureStrings(
        pageTitle: "Quick toggles",
        hubDescription: "One-click actions like dark mode and Trash",
        panelCaption: "One-click system actions in the menu bar panel and in the quick panel.",
        darkModeToDark: "Switch to dark mode",
        darkModeToLight: "Switch to light mode",
        darkModeCaption: "Changes the appearance of the whole system.",
        emptyTrashTitle: "Empty the Trash",
        emptyTrashCaption: "Removes everything from the Trash.",
        emptyTrashConfirmTitle: "Empty the Trash?",
        emptyTrashConfirmMessage: "All items in the Trash will be removed. This cannot be undone.",
        emptyTrashConfirmButton: "Empty the Trash",
        ejectTitle: "Eject all disks",
        ejectCaption: "Safely ejects every external disk.",
        hiddenFilesShow: "Show hidden files",
        hiddenFilesHide: "Hide hidden files",
        desktopIconsHide: "Hide desktop icons",
        desktopIconsShow: "Show desktop icons",
        finderRestartCaption: "The Finder restarts to apply it.",
        lockScreenTitle: "Lock the screen",
        lockScreenCaption: "Asks for the password to come back.",
        displayOffTitle: "Turn off the display",
        displayOffCaption: "The Mac keeps running with the display off.",
        screenSaverTitle: "Start the screen saver",
        screenSaverCaption: "Starts right away, on every display.",
        actionFailed: "Could not complete."
    )

    static let fr = QuickToggleFeatureStrings(
        pageTitle: "Actions rapides",
        hubDescription: "Actions en un clic comme le mode sombre et la Corbeille",
        panelCaption: "Actions système en un clic dans le panneau de la barre des menus et dans le panneau rapide.",
        darkModeToDark: "Passer en mode sombre",
        darkModeToLight: "Passer en mode clair",
        darkModeCaption: "Change l’apparence de tout le système.",
        emptyTrashTitle: "Vider la Corbeille",
        emptyTrashCaption: "Supprime tout le contenu de la Corbeille.",
        emptyTrashConfirmTitle: "Vider la Corbeille\u{00A0}?",
        emptyTrashConfirmMessage: "Tous les éléments de la Corbeille seront supprimés. Cette action est définitive.",
        emptyTrashConfirmButton: "Vider la Corbeille",
        ejectTitle: "Éjecter tous les disques",
        ejectCaption: "Éjecte en toute sécurité tous les disques externes.",
        hiddenFilesShow: "Afficher les fichiers masqués",
        hiddenFilesHide: "Masquer les fichiers masqués",
        desktopIconsHide: "Masquer les icônes du bureau",
        desktopIconsShow: "Afficher les icônes du bureau",
        finderRestartCaption: "Le Finder redémarre pour appliquer.",
        lockScreenTitle: "Verrouiller l’écran",
        lockScreenCaption: "Demande le mot de passe au retour.",
        displayOffTitle: "Éteindre l’écran",
        displayOffCaption: "Le Mac continue de fonctionner écran éteint.",
        screenSaverTitle: "Lancer l’économiseur d’écran",
        screenSaverCaption: "Démarre aussitôt, sur tous les écrans.",
        actionFailed: "Impossible de terminer."
    )

}
