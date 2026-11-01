// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct MouseButtonFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enableLabel: String
    let enableCaption: String
    let addButton: String
    let captureWaiting: String
    let captureCancel: String
    let captureBlind: String
    let captureUnsupported: String
    let captureWheel: String
    let captureExists: String
    let captureHint: String
    let backButtonName: String
    let forwardButtonName: String
    let otherButtonFormat: String      // "Button %d"
    let setShortcutButton: String
    let removeButton: String
    let emptyCaption: String
    let rowWheelNote: String
    let manageButton: String
    let panelCaption: String
    let sideWheelLeftName: String
    let sideWheelRightName: String
    let spacesEnableLabel: String
    let spacesEnableCaption: String
    let spacesPickButton: String
    let spacesShortcutsOffNote: String
    // The drag capture cannot borrow the shortcut capture's strings: it
    // refuses the side wheel by design, and its refusals must not point at a
    // list that is off screen with the shortcut switch off. New fields, so the
    // memberwise initializer makes a missing language a compile error.
    let spacesCaptureWaiting: String
    let spacesCaptureUnsupported: String
    let spacesCaptureExists: String
    let spacesFollowsDragLabel: String
    let spacesFollowsDragCaption: String
}

extension FeatureStrings {
    static func mouseButtons(_ language: AppLanguage) -> MouseButtonFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension MouseButtonFeatureStrings {
    static let enUS = MouseButtonFeatureStrings(
        pageTitle: "Mouse button shortcuts",
        hubDescription: "Extra buttons and side-wheel directions press a key combination you choose.",
        enableLabel: "Use extra buttons as shortcuts",
        enableCaption: "Each extra button or side-wheel direction can press a key combination for you. While it has a shortcut, it stops doing what it did before.",
        addButton: "Add a button or side wheel",
        captureWaiting: "Now press an extra button or move the side wheel.",
        captureCancel: "Cancel",
        captureBlind: "Mac Island cannot watch the mouse right now.",
        captureUnsupported: "That input cannot take a shortcut. Use an extra button or a side-wheel direction.",
        captureWheel: "That button already opens the radial menu. Pick another one, or free it there first.",
        captureExists: "That button or direction is already on the list below.",
        captureHint: "If nothing happens, your mouse’s own software may already be using that control.",
        backButtonName: "Back side button",
        forwardButtonName: "Forward side button",
        otherButtonFormat: "Button %d",
        setShortcutButton: "Set shortcut",
        removeButton: "Remove",
        emptyCaption: "No shortcuts yet. Add a button or side-wheel direction.",
        rowWheelNote: "This button opens the radial menu now, so the shortcut waits.",
        manageButton: "Set up…",
        panelCaption: "Extra buttons and side-wheel directions press key combinations you choose.",
        sideWheelLeftName: "Side wheel left",
        sideWheelRightName: "Side wheel right",
        spacesEnableLabel: "Switch Spaces by dragging a button",
        spacesEnableCaption: "Hold the chosen button and drag: left or right moves one Space over, up opens Mission Control, down opens App Exposé. A short click still does what it always did.",
        spacesPickButton: "Choose a button",
        spacesShortcutsOffNote: "The Mission Control keyboard shortcuts are switched off in System Settings, so this gesture has nothing to ask for.",
        spacesCaptureWaiting: "Now press an extra button.",
        spacesCaptureUnsupported: "That input cannot be held for a drag. Use an extra button.",
        spacesCaptureExists: "That button already has a shortcut. Pick another one.",
        spacesFollowsDragLabel: "Spaces follow the drag",
        spacesFollowsDragCaption: "Dragging right brings the Space on the left, the way a trackpad swipe carries it along with your fingers."
    )

    static let fr = MouseButtonFeatureStrings(
        pageTitle: "Raccourcis sur les boutons de la souris",
        hubDescription: "Les boutons supplémentaires et les directions de la molette latérale appuient sur une combinaison de touches de votre choix.",
        enableLabel: "Utiliser les boutons supplémentaires comme raccourcis",
        enableCaption: "Chaque bouton supplémentaire ou direction de la molette latérale peut appuyer sur une combinaison de touches pour vous. Tant qu’un raccourci lui est attribué, son ancienne action est suspendue.",
        addButton: "Ajouter un bouton ou la molette latérale",
        captureWaiting: "Appuyez sur un bouton supplémentaire ou tournez la molette latérale.",
        captureCancel: "Annuler",
        captureBlind: "Mac Island ne peut pas observer la souris pour le moment.",
        captureUnsupported: "Cette commande ne peut pas recevoir de raccourci. Utilisez un bouton supplémentaire ou une direction de la molette latérale.",
        captureWheel: "Ce bouton ouvre déjà le menu radial. Choisissez-en un autre, ou libérez-le là-bas d’abord.",
        captureExists: "Ce bouton ou cette direction est déjà dans la liste ci-dessous.",
        captureHint: "Si rien ne se passe, le logiciel de la souris utilise peut-être déjà cette commande.",
        backButtonName: "Bouton latéral précédent",
        forwardButtonName: "Bouton latéral suivant",
        otherButtonFormat: "Bouton %d",
        setShortcutButton: "Définir le raccourci",
        removeButton: "Supprimer",
        emptyCaption: "Aucun raccourci pour l’instant. Ajoutez un bouton ou une direction de la molette latérale.",
        rowWheelNote: "Ce bouton ouvre le menu radial en ce moment, le raccourci attend donc.",
        manageButton: "Configurer…",
        panelCaption: "Les boutons supplémentaires et les directions de la molette latérale appuient sur des combinaisons de touches de votre choix.",
        sideWheelLeftName: "Molette latérale vers la gauche",
        sideWheelRightName: "Molette latérale vers la droite",
        spacesEnableLabel: "Changer d’espace en faisant glisser un bouton",
        spacesEnableCaption: "Maintenez le bouton choisi et faites glisser\u{00A0}: à gauche ou à droite pour changer d’espace, vers le haut pour Mission Control, vers le bas pour Exposé d’app. Un clic bref fait toujours ce qu’il faisait avant.",
        spacesPickButton: "Choisir un bouton",
        spacesShortcutsOffNote: "Les raccourcis clavier de Mission Control sont désactivés dans Réglages Système, donc ce geste n’a rien à demander.",
        spacesCaptureWaiting: "Appuyez sur un bouton supplémentaire.",
        spacesCaptureUnsupported: "Cette commande ne peut pas être maintenue pour un glissement. Utilisez un bouton supplémentaire.",
        spacesCaptureExists: "Ce bouton a déjà un raccourci. Choisissez-en un autre.",
        spacesFollowsDragLabel: "Les espaces suivent le glissement",
        spacesFollowsDragCaption: "Glisser vers la droite amène l’espace de gauche, comme un balayage sur le trackpad qui l’emporte avec les doigts."
    )

}
