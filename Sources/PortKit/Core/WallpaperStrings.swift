// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Wallpaper panel strings.
struct WallpaperFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    /// Sentence form for the panel layout list, whose descriptions end in a stop.
    let panelDescription: String
    let filterAll: String
    let filterOwn: String
    let filterApple: String
    let applyAllDisplays: String
    let addImage: String
    let addFolder: String
    let removeAdded: String
    let doneRemoving: String
    let sourceUnavailable: String
    let addImagePrompt: String
    let addFolderPrompt: String
    let openSystemSettings: String
    let emptyAll: String
    let emptyOwn: String
    let emptyApple: String
    let downloading: String
    let downloadFailed: String
    let applyFailed: String
    let previousPage: String
    let nextPage: String
}

extension FeatureStrings {
    static func wallpaper(_ language: AppLanguage) -> WallpaperFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension WallpaperFeatureStrings {
    static let enUS = WallpaperFeatureStrings(
        pageTitle: "Wallpaper",
        hubDescription: "Pick a still wallpaper without opening System Settings",
        panelDescription: "Pick a still wallpaper without opening System Settings.",
        filterAll: "All",
        filterOwn: "Your pictures",
        filterApple: "Apple",
        applyAllDisplays: "Show on all Spaces",
        addImage: "Add image",
        addFolder: "Add folder",
        removeAdded: "Remove",
        doneRemoving: "Done",
        sourceUnavailable: "Unavailable",
        addImagePrompt: "Choose images to keep in Mac Island’s wallpaper list",
        addFolderPrompt: "Choose a folder of images to keep in Mac Island’s wallpaper list",
        openSystemSettings: "Open Wallpaper settings",
        emptyAll: "No wallpapers found",
        emptyOwn: "No pictures added yet",
        emptyApple: "No Apple stills found",
        downloading: "Downloading…",
        downloadFailed: "Could not download the wallpaper",
        applyFailed: "Could not set the wallpaper",
        previousPage: "Previous",
        nextPage: "Next"
    )

    static let fr = WallpaperFeatureStrings(
        pageTitle: "Fond d’écran",
        hubDescription: "Choisissez une image fixe sans ouvrir Réglages Système",
        panelDescription: "Choisissez une image fixe sans ouvrir Réglages Système.",
        filterAll: "Tous",
        filterOwn: "Seulement les vôtres",
        filterApple: "Seulement Apple",
        applyAllDisplays: "Afficher sur tous les Spaces",
        addImage: "Ajouter une image",
        addFolder: "Ajouter un dossier",
        removeAdded: "Retirer",
        doneRemoving: "Terminé",
        sourceUnavailable: "Indisponible",
        addImagePrompt: "Choisissez des images pour la liste Mac Island",
        addFolderPrompt: "Choisissez un dossier d’images pour la liste Mac Island",
        openSystemSettings: "Ouvrir les réglages de fond d’écran",
        emptyAll: "Aucun fond d’écran trouvé",
        emptyOwn: "Aucune image ajoutée pour l’instant",
        emptyApple: "Aucun fond Apple trouvé",
        downloading: "Téléchargement…",
        downloadFailed: "Impossible de télécharger le fond d’écran",
        applyFailed: "Impossible de définir le fond d’écran",
        previousPage: "Précédent",
        nextPage: "Suivant"
    )

}
