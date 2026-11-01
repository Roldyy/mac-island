// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct WhatsAppOrganizerStrings {
    let title: String
    let experimental: String
    let description: String
    let enabled: String
    let enabledCaption: String
    let destination: String
    let chooseFolder: String
    let useDefault: String
    let invalidDestination: String
    let organization: String
    let flat: String
    let byType: String
    let byMonth: String
    let delay: String
    let minutesFormat: String
    let duplicateAction: String
    let trashDuplicate: String
    let keepBoth: String
    let replaceExisting: String
    let duplicateCaption: String
    let organizeNow: String
    let undo: String
    let waiting: String
    let working: String
    let resultFormat: String
    let lastRunFormat: String
    let neverRun: String
    let notificationTitle: String
    let notificationFormat: String
    let privacyNote: String

    static func localized(_ language: AppLanguage) -> WhatsAppOrganizerStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension WhatsAppOrganizerStrings {
    static let enUS = WhatsAppOrganizerStrings(
        title: "Automatic organization",
        experimental: "Experimental",
        description: "Moves stable WhatsApp downloads to a dedicated folder and detects exact repeat downloads.",
        enabled: "Organize automatically",
        enabledCaption: "WhatsApp may download a moved file again. Mac Island cannot prevent the network download, but it can detect and discard an identical extra copy.",
        destination: "Destination folder",
        chooseFolder: "Choose…",
        useDefault: "Use Downloads/WhatsApp",
        invalidDestination: "Choose a folder other than Downloads itself.",
        organization: "Folder structure",
        flat: "No subfolders",
        byType: "By file type",
        byMonth: "By year and month",
        delay: "Wait before moving",
        minutesFormat: "%d minutes",
        duplicateAction: "When the same file is downloaded again",
        trashDuplicate: "Move the new copy to Trash",
        keepBoth: "Keep both copies",
        replaceExisting: "Replace the organized copy",
        duplicateCaption: "Duplicates are confirmed with a private SHA-256 digest. The organized copy is rechecked before another copy is discarded.",
        organizeNow: "Organize eligible files now",
        undo: "Undo last organization",
        waiting: "Watching Downloads",
        working: "Organizing WhatsApp files…",
        resultFormat: "%1$d moved · %2$d duplicates · %3$d failed",
        lastRunFormat: "Last organization %@: %d moved · %d duplicates · %d failed",
        neverRun: "No organization has run yet.",
        notificationTitle: "WhatsApp organization",
        notificationFormat: "%1$d files organized. %2$d duplicate downloads handled. %3$d failed.",
        privacyNote: "To identify exact duplicates, file bytes are read locally only while calculating a cryptographic digest. Contents and chats are never stored or uploaded."
    )

    static let fr = WhatsAppOrganizerStrings(
        title: "Organisation automatique",
        experimental: "Expérimental",
        description: "Déplace les téléchargements WhatsApp stables vers un dossier dédié et détecte les téléchargements répétés identiques.",
        enabled: "Organiser automatiquement",
        enabledCaption: "WhatsApp peut retélécharger un fichier déplacé. Mac Island ne peut pas empêcher le téléchargement réseau, mais peut détecter et écarter une copie supplémentaire identique.",
        destination: "Dossier de destination",
        chooseFolder: "Choisir…",
        useDefault: "Utiliser Téléchargements/WhatsApp",
        invalidDestination: "Choisissez un dossier autre que Téléchargements lui-même.",
        organization: "Structure des dossiers",
        flat: "Sans sous-dossiers",
        byType: "Par type de fichier",
        byMonth: "Par année et mois",
        delay: "Attendre avant de déplacer",
        minutesFormat: "%d minutes",
        duplicateAction: "Quand le même fichier est téléchargé à nouveau",
        trashDuplicate: "Placer la nouvelle copie dans la Corbeille",
        keepBoth: "Conserver les deux copies",
        replaceExisting: "Remplacer la copie organisée",
        duplicateCaption: "Les doublons sont confirmés par une empreinte SHA-256 privée. La copie organisée est revérifiée avant qu’une autre copie soit écartée.",
        organizeNow: "Organiser les fichiers éligibles maintenant",
        undo: "Annuler la dernière organisation",
        waiting: "Surveillance de Téléchargements",
        working: "Organisation des fichiers WhatsApp…",
        resultFormat: "%1$d déplacés · %2$d doublons · %3$d échecs",
        lastRunFormat: "Dernière organisation %@\u{00A0}: %d déplacés · %d doublons · %d échecs",
        neverRun: "Aucune organisation effectuée pour le moment.",
        notificationTitle: "Organisation WhatsApp",
        notificationFormat: "%1$d fichiers organisés. %2$d téléchargements en double traités. %3$d échecs.",
        privacyNote: "Pour identifier les doublons exacts, les octets des fichiers sont lus localement uniquement pendant le calcul d’une empreinte cryptographique. Les contenus et les discussions ne sont jamais stockés ni envoyés."
    )

}
