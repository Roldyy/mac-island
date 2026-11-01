// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct FeedbackStrings {
    let sectionTitle: String
    let sectionCaption: String
    let openButton: String
    let windowTitle: String
    let bugTitle: String
    let featureTitle: String
    let messageLabel: String
    let bugPlaceholder: String
    let featurePlaceholder: String
    let charactersFormat: String
    let includeDiagnostics: String
    let includeDiagnosticsCaption: String
    let whatSentTitle: String
    let whatSentBasic: String
    let whatSentDiagnostics: String
    let privacyNote: String
    let retentionNote: String
    let sendButton: String
    let sending: String
    let sentTitle: String
    let sentCaption: String
    let unavailableError: String
    let rateLimitError: String
    let genericError: String
    let done: String
    let commandBug: String
    let commandFeature: String
    let commandSubtitle: String
    let diagnosticsChannelLabel: String
}

extension FeatureStrings {
    static func feedback(_ language: AppLanguage) -> FeedbackStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension FeedbackStrings {
    static let enUS = FeedbackStrings(
        sectionTitle: "Feedback",
        sectionCaption: "Send a bug report or feature idea directly to the person who maintains Mac Island.",
        openButton: "Send feedback",
        windowTitle: "Send feedback",
        bugTitle: "Bug",
        featureTitle: "Feature idea",
        messageLabel: "What would you like to share?",
        bugPlaceholder: "Tell me what happened and what you expected.",
        featurePlaceholder: "Describe the idea and how it would help.",
        charactersFormat: "%d of 2000 characters",
        includeDiagnostics: "Include technical details",
        includeDiagnosticsCaption: "Adds only the technical details shown below. It does not include logs.",
        whatSentTitle: "What will be sent",
        whatSentBasic: "Your chosen category and the text above.",
        whatSentDiagnostics: "The technical details listed below.",
        privacyNote: "No name, account, email, device identifier, logs, screenshots, files or clipboard content are included. Your public IP is temporarily processed for abuse protection and is not attached to the feedback.",
        retentionNote: "After delivery, the text remains in private support channels until the service owner deletes it. An undelivered copy is permanently deleted after 7 days.",
        sendButton: "Send feedback",
        sending: "Sending…",
        sentTitle: "Feedback sent",
        sentCaption: "Thank you. No contact information was sent, so you will not receive a direct reply.",
        unavailableError: "Could not connect. Check your internet connection and try again.",
        rateLimitError: "Too many submissions from this network. Please try again later.",
        genericError: "Could not send the feedback right now.",
        done: "Done",
        commandBug: "Report a bug",
        commandFeature: "Suggest a feature",
        commandSubtitle: "Send feedback",
        diagnosticsChannelLabel: "Update channel"
    )

    static let fr = FeedbackStrings(
        sectionTitle: "Avis",
        sectionCaption: "Envoyez un rapport de bug ou une idée directement à la personne qui maintient Mac Island.",
        openButton: "Envoyer un avis",
        windowTitle: "Envoyer un avis",
        bugTitle: "Bug",
        featureTitle: "Idée de fonction",
        messageLabel: "Que souhaitez-vous partager\u{00A0}?",
        bugPlaceholder: "Décrivez ce qui s’est passé et ce que vous attendiez.",
        featurePlaceholder: "Décrivez l’idée et son utilité.",
        charactersFormat: "%d caractères sur 2000",
        includeDiagnostics: "Inclure les données techniques",
        includeDiagnosticsCaption: "Ajoute uniquement les données techniques affichées ci-dessous. Aucun journal.",
        whatSentTitle: "Ce qui sera envoyé",
        whatSentBasic: "La catégorie choisie et le texte ci-dessus.",
        whatSentDiagnostics: "Les données techniques listées ci-dessous.",
        privacyNote: "Aucun nom, compte, e-mail, identifiant d’appareil, journal, capture, fichier ou presse-papiers n’est inclus. Votre IP publique est traitée temporairement contre les abus et n’est pas jointe à l’avis.",
        retentionNote: "Après livraison, le texte reste dans des canaux privés jusqu’à sa suppression par le responsable. Une copie non livrée est définitivement supprimée après 7 jours.",
        sendButton: "Envoyer l’avis",
        sending: "Envoi…",
        sentTitle: "Avis envoyé",
        sentCaption: "Merci. Aucune coordonnée n’a été envoyée, vous ne recevrez donc pas de réponse directe.",
        unavailableError: "Connexion impossible. Vérifiez Internet et réessayez.",
        rateLimitError: "Trop d’envois depuis ce réseau. Réessayez plus tard.",
        genericError: "Impossible d’envoyer l’avis maintenant.",
        done: "Terminé",
        commandBug: "Signaler un bug",
        commandFeature: "Suggérer une fonction",
        commandSubtitle: "Envoyer un avis",
        diagnosticsChannelLabel: "Canal de mise à jour"
    )

}
