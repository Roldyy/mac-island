// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Strings for the settings backup (export and import on the Advanced page).
/// Same contract as the other FeatureStrings structs: memberwise init in
/// declaration order, one static per language, all in this file.
struct BackupFeatureStrings {
    let title: String
    let description: String
    let exportButton: String
    let importButton: String
    let exported: String
    let exportFailed: String
    let importConfirmTitle: String
    let importConfirmBody: String
    let importMissingIslandBody: String
    let importAction: String
    let invalidFile: String
}

extension FeatureStrings {
    static func backup(_ language: AppLanguage) -> BackupFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension BackupFeatureStrings {
}

extension BackupFeatureStrings {
    static let enUS = BackupFeatureStrings(
        title: "Backup",
        description: "Take your setup to another Mac: export every preference to a file and import it there. Your Scratchpad notes, clipboard history, Shelf items and system permissions never leave this Mac.",
        exportButton: "Export settings…",
        importButton: "Import settings…",
        exported: "Backup saved",
        exportFailed: "Could not save the backup.",
        importConfirmTitle: "Import these settings?",
        importConfirmBody: "Your current settings are replaced by the file’s and the app restarts. Nothing else on this Mac is touched.",
        importMissingIslandBody: "This backup has no Dynamic Island settings. This Mac’s island settings will be kept. Re-export with Mac Island 3.4 or newer on the other Mac to copy them. Other settings will be imported and the app will restart.",
        importAction: "Import and restart",
        invalidFile: "This file is not a valid Mac Island backup."
    )

    static let fr = BackupFeatureStrings(
        title: "Sauvegarde",
        description: "Emportez votre configuration sur un autre Mac\u{00A0}: exportez toutes les préférences dans un fichier et importez-le là-bas. Le texte de vos notes dans Brouillon, l’historique du presse-papiers, les éléments de l’étagère et les autorisations système ne quittent jamais ce Mac.",
        exportButton: "Exporter les réglages…",
        importButton: "Importer les réglages…",
        exported: "Sauvegarde enregistrée",
        exportFailed: "Impossible d’enregistrer la sauvegarde.",
        importConfirmTitle: "Importer ces réglages\u{00A0}?",
        importConfirmBody: "Les réglages actuels sont remplacés par ceux du fichier et l’app redémarre. Rien d’autre ne change sur ce Mac.",
        importMissingIslandBody: "Cette sauvegarde ne contient aucun réglage de Dynamic Island. Les réglages de ce Mac seront conservés. Pour les copier depuis l’autre Mac, exportez à nouveau avec Mac Island 3.4 ou une version ultérieure. Les autres réglages seront importés, puis l’app redémarrera.",
        importAction: "Importer et redémarrer",
        invalidFile: "Ce fichier n’est pas une sauvegarde Mac Island valide."
    )

}
