// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct RecorderShareStrings {
    let caption: String
    let privacyData: String
    let privacyStorage: String
    let privacyAccess: String
    let compressing: String
    let uploading: String
    let tooLarge: String
    let failed: String
    let tourCaption: String
}

extension FeatureStrings {
    static func recorderShare(_ language: AppLanguage) -> RecorderShareStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension RecorderShareStrings {
    static let enUS = RecorderShareStrings(
        caption: "Choose 1 or 6 hours. The final video is compressed on this Mac to fit under 100 MB and deleted automatically.",
        privacyData: "Mac Island sends only the final video created from this recording, including the audio you kept, and the expiration you choose. It does not send your name, account or device identifier.",
        privacyStorage: "Network providers and the service temporarily process your public IP to prevent abuse. The video and link metadata are permanently deleted when you delete the link or its time ends. The service does not create backups.",
        privacyAccess: "Anyone with the link can view, download, save or redistribute the video. Active links are available to the service operator for abuse moderation. Share only with people you trust.",
        compressing: "Compressing for sharing…",
        uploading: "Uploading securely…",
        tooLarge: "This recording cannot fit under 100 MB without losing too much quality.",
        failed: "The temporary link could not be created",
        tourCaption: "Compress a finished recording on this Mac and share it for 1 or 6 hours."
    )

    static let fr = RecorderShareStrings(
        caption: "Choisissez 1 ou 6 heures. La vidéo finale est compressée sur ce Mac à moins de 100 Mo, puis supprimée automatiquement.",
        privacyData: "Mac Island envoie uniquement la vidéo finale créée à partir de cet enregistrement, avec l’audio conservé, et la durée choisie. Votre nom, compte et identifiant d’appareil ne sont pas envoyés.",
        privacyStorage: "Les fournisseurs réseau et le service traitent temporairement votre adresse IP publique pour prévenir les abus. La vidéo et les données du lien sont définitivement supprimées quand vous effacez le lien ou à son expiration. Le service ne crée aucune sauvegarde.",
        privacyAccess: "Toute personne disposant du lien peut voir, télécharger, enregistrer ou redistribuer la vidéo. Les liens actifs sont accessibles à l’opérateur du service pour modérer les abus. Partagez-les uniquement avec des personnes de confiance.",
        compressing: "Compression pour le partage…",
        uploading: "Envoi sécurisé…",
        tooLarge: "Cet enregistrement ne peut pas tenir sous 100 Mo sans perdre trop de qualité.",
        failed: "Impossible de créer le lien temporaire",
        tourCaption: "Compressez un enregistrement terminé sur ce Mac et partagez-le pendant 1 ou 6 heures."
    )

}
