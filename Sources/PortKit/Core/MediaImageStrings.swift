// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct MediaImageConverterStrings {
    let filesSelectedFormat: String
    let profile: String
    let noProfile: String
    let profileName: String
    let saveAsNew: String
    let updateProfile: String
    let deleteProfile: String
    let profileModified: String
    let profileDefaultNameFormat: String
    let presetWeb: String
    let presetSocial: String
    let presetDocs: String
    let resize: String
    let resizeNone: String
    let resizeMax: String
    let resizeWidth: String
    let resizeHeight: String
    let resizeExact: String
    let exactStretch: String
    let exactFit: String
    let exactFill: String
    let height: String
    let watermark: String
    let watermarkOff: String
    let watermarkText: String
    let watermarkLogo: String
    let watermarkBoth: String
    let watermarkTextPlaceholder: String
    let noLogo: String
    let chooseLogo: String
    let position: String
    let topLeft: String
    let topRight: String
    let center: String
    let bottomLeft: String
    let bottomRight: String
    let opacity: String
    let margin: String
    let scale: String
    let rename: String
    let preview: String
    let outputName: String
    let background: String
    let backgroundTransparent: String
    let backgroundWhite: String
    let backgroundBlack: String
    let preserveDate: String
    let saveInSubfolder: String
    let moreOptions: String
    let tooLarge: String
    let copySummary: String
    let savedBytesFormat: String
    let grewBytesFormat: String
    let batchSavedFormat: String
    let batchPartialFormat: String
    let batchSummaryHeaderFormat: String
    let batchSummaryItemFormat: String

    static func localized(_ language: AppLanguage) -> MediaImageConverterStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension MediaImageConverterStrings {
    static let enUS = MediaImageConverterStrings(
        filesSelectedFormat: "%d files selected",
        profile: "Profile",
        noProfile: "No profile",
        profileName: "Profile name",
        saveAsNew: "Save new",
        updateProfile: "Update",
        deleteProfile: "Delete profile",
        profileModified: "Modified",
        profileDefaultNameFormat: "Profile %d",
        presetWeb: "Web",
        presetSocial: "Social",
        presetDocs: "Docs",
        resize: "Resize",
        resizeNone: "No change",
        resizeMax: "Max side",
        resizeWidth: "Width",
        resizeHeight: "Height",
        resizeExact: "Custom",
        exactStretch: "Stretch",
        exactFit: "Fit",
        exactFill: "Fill",
        height: "Height",
        watermark: "Watermark",
        watermarkOff: "Off",
        watermarkText: "Text",
        watermarkLogo: "Logo",
        watermarkBoth: "Text + logo",
        watermarkTextPlaceholder: "Watermark text",
        noLogo: "No logo",
        chooseLogo: "Choose logo",
        position: "Position",
        topLeft: "Top left",
        topRight: "Top right",
        center: "Center",
        bottomLeft: "Bottom left",
        bottomRight: "Bottom right",
        opacity: "Opacity",
        margin: "Margin",
        scale: "Scale",
        rename: "Rename",
        preview: "Preview",
        outputName: "Output",
        background: "Background",
        backgroundTransparent: "Transparent",
        backgroundWhite: "White",
        backgroundBlack: "Black",
        preserveDate: "Keep original modified date",
        saveInSubfolder: "Save in “Converted” subfolder",
        moreOptions: "More options",
        tooLarge: "These dimensions are too large to process safely. Choose a smaller size.",
        copySummary: "Copy summary",
        savedBytesFormat: "%@ saved",
        grewBytesFormat: "%@ larger",
        batchSavedFormat: "%d images saved",
        batchPartialFormat: "%d saved, %d failed",
        batchSummaryHeaderFormat: "%d saved, %d failed",
        batchSummaryItemFormat: "%@ -> %@"
    )

    static let fr = MediaImageConverterStrings(
        filesSelectedFormat: "%d fichiers sélectionnés",
        profile: "Profil",
        noProfile: "Aucun profil",
        profileName: "Nom du profil",
        saveAsNew: "Enregistrer un nouveau",
        updateProfile: "Mettre à jour",
        deleteProfile: "Supprimer le profil",
        profileModified: "Modifié",
        profileDefaultNameFormat: "Profil %d",
        presetWeb: "Web",
        presetSocial: "Réseaux sociaux",
        presetDocs: "Documents",
        resize: "Redimensionner",
        resizeNone: "Aucun changement",
        resizeMax: "Côté maximal",
        resizeWidth: "Largeur",
        resizeHeight: "Hauteur",
        resizeExact: "Personnalisé",
        exactStretch: "Étirer",
        exactFit: "Ajuster",
        exactFill: "Remplir",
        height: "Hauteur",
        watermark: "Filigrane",
        watermarkOff: "Désactivé",
        watermarkText: "Texte",
        watermarkLogo: "Logo",
        watermarkBoth: "Texte + logo",
        watermarkTextPlaceholder: "Texte du filigrane",
        noLogo: "Aucun logo",
        chooseLogo: "Choisir un logo",
        position: "Position",
        topLeft: "En haut à gauche",
        topRight: "En haut à droite",
        center: "Centre",
        bottomLeft: "En bas à gauche",
        bottomRight: "En bas à droite",
        opacity: "Opacité",
        margin: "Marge",
        scale: "Échelle",
        rename: "Renommer",
        preview: "Aperçu",
        outputName: "Sortie",
        background: "Arrière-plan",
        backgroundTransparent: "Transparent",
        backgroundWhite: "Blanc",
        backgroundBlack: "Noir",
        preserveDate: "Conserver la date de modification d’origine",
        saveInSubfolder: "Enregistrer dans le sous-dossier «\u{00A0}Converted\u{00A0}»",
        moreOptions: "Plus d’options",
        tooLarge: "Ces dimensions sont trop grandes pour un traitement sûr. Choisissez une taille plus petite.",
        copySummary: "Copier le résumé",
        savedBytesFormat: "%@ économisés",
        grewBytesFormat: "%@ plus grand",
        batchSavedFormat: "%d images enregistrées",
        batchPartialFormat: "%d enregistrées, %d échouées",
        batchSummaryHeaderFormat: "%d enregistrées, %d échouées",
        batchSummaryItemFormat: "%@ -> %@"
    )

}
