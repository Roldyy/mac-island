// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchFilesStrings {
    let archive: String
    let archiveHint: String
    let saved: String
    let downloadsTitle: String
    let downloadsDescription: String
    let downloadsHint: String
    let chooseFolder: String
    let folderUnavailable: String
    let waiting: String
    let inProgress: String
    let totalUnknown: String
    let completed: String
    let clearFolder: String
    let optimizeMedia: String
    let optimizeDropHint: String
    let resumeMedia: String
}

extension FeatureStrings {
    static func notchFiles(_ language: AppLanguage) -> NotchFilesStrings {
        switch language {
        case .enUS: return NotchFilesStrings(
            archive: "Create ZIP",
            archiveHint: "Each selected item is saved as a separate ZIP. Originals stay unchanged.",
            saved: "Saved",
            downloadsTitle: "Downloads",
            downloadsDescription: "See files arriving in a folder you choose, directly in the Dynamic Island.",
            downloadsHint: "Choose the folder where your browser saves downloads. Only that folder is watched.",
            chooseFolder: "Choose Folder…",
            folderUnavailable: "This folder is unavailable. Choose it again to restore access.",
            waiting: "No files in this folder",
            inProgress: "Downloading",
            totalUnknown: "Total size unavailable",
            completed: "Download complete",
            clearFolder: "Forget Folder",
            optimizeMedia: "Optimize media",
            optimizeDropHint: "Drag images or one video onto the island, then drop on Optimize media to choose how to save a copy.",
            resumeMedia: "Return to media")
        default: return NotchFilesStrings(
            archive: "Créer un ZIP",
            archiveHint: "Chaque élément sélectionné est enregistré dans un ZIP distinct. Les originaux sont conservés.",
            saved: "Enregistré",
            downloadsTitle: "Téléchargements",
            downloadsDescription: "Voyez les fichiers arriver dans un dossier choisi, directement dans le Dynamic Island.",
            downloadsHint: "Choisissez le dossier où votre navigateur enregistre les téléchargements. Seul ce dossier est suivi.",
            chooseFolder: "Choisir un dossier…",
            folderUnavailable: "Ce dossier est indisponible. Choisissez-le à nouveau pour rétablir l’accès.",
            waiting: "Aucun fichier dans ce dossier",
            inProgress: "Téléchargement",
            totalUnknown: "Taille totale indisponible",
            completed: "Téléchargement terminé",
            clearFolder: "Oublier le dossier",
            optimizeMedia: "Optimiser les médias",
            optimizeDropHint: "Faites glisser des images ou une vidéo sur l’îlot, puis déposez-les sur Optimiser les médias pour choisir comment enregistrer une copie.",
            resumeMedia: "Revenir aux médias")
        }
    }
}
