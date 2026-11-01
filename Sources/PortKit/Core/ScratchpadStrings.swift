// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Localized strings for the scratchpad, the floating pad for short-lived text.
struct ScratchpadFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let placeholder: String
    let copyAll: String
    let copied: String
    let exportAction: String
    let exportFailed: String
    let loadFailed: String
    let saveFailed: String
    let clearAction: String
    let retentionTitle: String
    let retentionNever: String
    let retentionDay: String
    let retentionWeek: String
    let retentionMonth: String
    let retentionCaption: String
    let closeOnClickOutside: String
    let keepOpen: String
    let backgroundOpacity: String
    let backgroundTranslucent: String
    let backgroundOpaque: String
    let newPad: String
    let padActions: String
    let renamePad: String
    let closePad: String
    let saveName: String
    let cancel: String
    let deletePadMessageFormat: String
    let padLimitFormat: String
    let previewFormatting: String
    let editText: String
    /// How a task's checkbox in the formatted reading tells VoiceOver whether
    /// it is done.
    let taskDone: String
    let taskNotDone: String
    let markBold: String
    let markItalic: String
    let markStrikethrough: String
    let markHeading: String
    let markBullet: String
    let markNumbered: String
    let markQuote: String
    let markCode: String
    let markLink: String
    let formatMarks: String
    let textSize: String
}

extension FeatureStrings {
    static func scratchpad(_ language: AppLanguage) -> ScratchpadFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension ScratchpadFeatureStrings {
    static let enUS = ScratchpadFeatureStrings(
        pageTitle: "Scratchpad",
        hubDescription: "Floating pads for short-lived notes",
        panelCaption: "Quick notes in separate tabs",
        openButton: "Open scratchpad",
        placeholder: "Type anything. It saves by itself.",
        copyAll: "Copy all",
        copied: "Copied",
        exportAction: "Save as file",
        exportFailed: "The file could not be saved",
        loadFailed: "Your notes could not be opened. They were left unchanged.",
        saveFailed: "Your notes could not be saved. Copy them elsewhere before quitting.",
        clearAction: "Clear",
        retentionTitle: "Clear on its own",
        retentionNever: "Never",
        retentionDay: "After a day unused",
        retentionWeek: "After a week unused",
        retentionMonth: "After a month unused",
        retentionCaption: "The pad empties itself once the text goes that long without edits.",
        closeOnClickOutside: "Close when I click outside",
        keepOpen: "Keep open",
        backgroundOpacity: "Pad background",
        backgroundTranslucent: "Translucent",
        backgroundOpaque: "Opaque",
        newPad: "New scratchpad",
        padActions: "Scratchpad actions",
        renamePad: "Rename scratchpad",
        closePad: "Close scratchpad",
        saveName: "Save",
        cancel: "Cancel",
        deletePadMessageFormat: "Delete “%@” and everything in it?",
        padLimitFormat: "You can keep up to %d scratchpads",
        previewFormatting: "Show formatting",
        editText: "Edit text",
        taskDone: "Done",
        taskNotDone: "Not done",
        markBold: "Bold",
        markItalic: "Italic",
        markStrikethrough: "Strikethrough",
        markHeading: "Heading",
        markBullet: "Bulleted list",
        markNumbered: "Numbered list",
        markQuote: "Quote",
        markCode: "Code",
        markLink: "Link",
        formatMarks: "Formatting",
        textSize: "Text size"
    )

    static let fr = ScratchpadFeatureStrings(
        pageTitle: "Brouillon",
        hubDescription: "Des blocs flottants à onglets pour les notes éphémères",
        panelCaption: "Des notes rapides dans des onglets séparés",
        openButton: "Ouvrir le brouillon",
        placeholder: "Écrivez ce que vous voulez. Tout s’enregistre tout seul.",
        copyAll: "Tout copier",
        copied: "Copié",
        exportAction: "Enregistrer dans un fichier",
        exportFailed: "Impossible d’enregistrer le fichier",
        loadFailed: "Impossible d’ouvrir les notes. Elles restent inchangées.",
        saveFailed: "Impossible d’enregistrer les notes. Copiez-les ailleurs avant de quitter.",
        clearAction: "Effacer",
        retentionTitle: "Effacer automatiquement",
        retentionNever: "Jamais",
        retentionDay: "Après un jour sans modification",
        retentionWeek: "Après une semaine sans modification",
        retentionMonth: "Après un mois sans modification",
        retentionCaption: "Le bloc se vide quand le texte reste aussi longtemps sans modification.",
        closeOnClickOutside: "Fermer si je clique à l’extérieur",
        keepOpen: "Garder ouvert",
        backgroundOpacity: "Fond du brouillon",
        backgroundTranslucent: "Translucide",
        backgroundOpaque: "Opaque",
        newPad: "Nouveau brouillon",
        padActions: "Actions du brouillon",
        renamePad: "Renommer le brouillon",
        closePad: "Fermer le brouillon",
        saveName: "Enregistrer",
        cancel: "Annuler",
        deletePadMessageFormat: "Supprimer «\u{00A0}%@\u{00A0}» et tout son contenu\u{00A0}?",
        padLimitFormat: "Vous pouvez conserver jusqu’à %d brouillons",
        previewFormatting: "Afficher la mise en forme",
        editText: "Modifier le texte",
        taskDone: "Terminée",
        taskNotDone: "Non terminée",
        markBold: "Gras",
        markItalic: "Italique",
        markStrikethrough: "Barré",
        markHeading: "Titre",
        markBullet: "Liste à puces",
        markNumbered: "Liste numérotée",
        markQuote: "Citation",
        markCode: "Code",
        markLink: "Lien",
        formatMarks: "Mise en forme",
        textSize: "Taille du texte"
    )

}

extension ScratchpadFeatureStrings {
    /// One place both toolbars read their labels from, so the floating pad and
    /// the island cannot drift into calling the same mark different things.
    func label(for mark: ScratchpadMark) -> String {
        switch mark {
        case .bold: return markBold
        case .italic: return markItalic
        case .strikethrough: return markStrikethrough
        case .heading: return markHeading
        case .bullet: return markBullet
        case .numbered: return markNumbered
        case .quote: return markQuote
        case .code: return markCode
        case .link: return markLink
        }
    }
}
