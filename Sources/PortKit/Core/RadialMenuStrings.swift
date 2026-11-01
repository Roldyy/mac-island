// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct RadialMenuFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enableLabel: String
    let enableCaption: String
    let positionLabel: String
    let positionPointer: String
    let positionCenter: String
    let tryButton: String
    let actionsHeader: String
    let addButton: String
    let limitCaption: String
    let emptyCaption: String
    let backButton: String
    let editActionsButton: String
    let nameLabel: String
    let automaticLabel: String
    let iconLabel: String
    let actionLabel: String
    let kindApp: String
    let kindFile: String
    let kindURL: String
    let kindShortcut: String
    let kindTool: String
    let kindMedia: String
    let kindSubmenu: String
    let chooseButton: String
    let urlPlaceholder: String
    let urlInvalid: String
    let toolLabel: String
    let mediaLabel: String
    let mediaPlayPause: String
    let mediaPrevious: String
    let mediaNext: String
    let mediaNowPlaying: String
    let mediaNothingPlaying: String
    let mediaOpenAppFormat: String
    let submenuCaption: String
    let saveButton: String
    let deleteButton: String
    let permissionCaption: String
    let manageButton: String
    let panelCaption: String
    let mouseTriggerLabel: String
    let mouseTriggerOff: String
    let mouseTriggerBack: String
    let mouseTriggerForward: String
    let mouseTriggerWarning: String
    let buttonTestLabel: String
    let buttonTestWaiting: String
    let buttonTestSeen: String
    let buttonTestOther: String
    let buttonTestBlind: String
    let buttonTestHint: String
    let activationModeLabel: String
    let activationModePressOrHold: String
    let activationModePress: String
    let activationModeHold: String
    let activationModeCaption: String
    let profilesHeader: String
    let profilePickerLabel: String
    let addProfileButton: String
    let duplicateProfileButton: String
    let deleteProfileButton: String
    let deleteProfileConfirmFormat: String
    let deleteProfileConfirmMessage: String
    let profileNameLabel: String
    let profileColorLabel: String
    let profileShortcutLabel: String
    let profileMouseTriggerLabel: String
    let presetGeneral: String
    let presetMedia: String
    let presetTools: String
    let presetWindowLayout: String
    let presetQuickToggles: String
    let presetBlank: String
    let colorAccent: String
    let colorBlue: String
    let colorPurple: String
    let colorPink: String
    let colorRed: String
    let colorOrange: String
    let colorYellow: String
    let colorGreen: String
    let colorMint: String
    let colorCyan: String
    let colorIndigo: String
    let colorGraphite: String
    let fetchFaviconButton: String
    let fetchFaviconDisclaimer: String
    let fetchFaviconLoading: String
    let fetchFaviconSuccess: String
    let fetchFaviconError: String
    let mouseTriggerRequirement: String
    let canvasHint: String
    let resetActionsButton: String
    let resetActionsConfirm: String
    let resetActionsConfirmMessage: String
    let showListButton: String
    let hideListButton: String
    let trackpadTapLabel: String
    let trackpadTapConflict: String
    let profileNoTrigger: String
}

extension FeatureStrings {
    static func radialMenu(_ language: AppLanguage) -> RadialMenuFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension RadialMenuFeatureStrings {
    static let enUS = RadialMenuFeatureStrings(
        pageTitle: "Radial menu",
        hubDescription: "Opens a wheel of your favorite actions around the pointer",
        enableLabel: "Use the radial menu",
        enableCaption: "Hold the shortcut, point at an action and release. A quick press keeps the wheel open.",
        positionLabel: "Opens",
        positionPointer: "At the pointer",
        positionCenter: "At the screen center",
        tryButton: "Try it",
        actionsHeader: "Actions",
        addButton: "Add action",
        limitCaption: "A wheel holds up to 12 actions.",
        emptyCaption: "No actions here yet.",
        backButton: "Back",
        editActionsButton: "Edit actions",
        nameLabel: "Name",
        automaticLabel: "Automatic",
        iconLabel: "Icon",
        actionLabel: "Action",
        kindApp: "Open an app",
        kindFile: "Open a file or folder",
        kindURL: "Open a link",
        kindShortcut: "Press a shortcut",
        kindTool: "Mac Island tool",
        kindMedia: "Media control",
        kindSubmenu: "Submenu",
        chooseButton: "Choose…",
        urlPlaceholder: "example.com",
        urlInvalid: "Enter a valid link.",
        toolLabel: "Tool",
        mediaLabel: "Control",
        mediaPlayPause: "Play or pause",
        mediaPrevious: "Previous track",
        mediaNext: "Next track",
        mediaNowPlaying: "Now Playing",
        mediaNothingPlaying: "Nothing playing",
        mediaOpenAppFormat: "Open %@",
        submenuCaption: "Opens a second wheel with its own actions.",
        saveButton: "Save",
        deleteButton: "Remove",
        permissionCaption: "Key actions and the side mouse button trigger need the Accessibility permission.",
        manageButton: "Manage the menu",
        panelCaption: "Your favorite actions on a wheel",
        mouseTriggerLabel: "Mouse button",
        mouseTriggerOff: "Off",
        mouseTriggerBack: "Back side button",
        mouseTriggerForward: "Forward side button",
        mouseTriggerWarning: "While this is on, that button no longer goes back or forward in apps. If you navigate with it, leave this off.",
        buttonTestLabel: "Button test",
        buttonTestWaiting: "Press the button now",
        buttonTestSeen: "Mac Island sees this button",
        buttonTestOther: "That was a different button",
        buttonTestBlind: "Mac Island cannot watch the mouse right now",
        buttonTestHint: "If nothing lights up, macOS is not sending that button to apps. Mice that come with their own software often turn the side buttons into something else. Change it back there, or give the button a key combination and use that combination above.",
        activationModeLabel: "Opening behavior",
        activationModePressOrHold: "Press or hold",
        activationModePress: "Press to open",
        activationModeHold: "Hold to select",
        activationModeCaption: "Press or hold keeps the current adaptive gesture. Press stays open; hold runs the highlighted action on release.",
        profilesHeader: "Profiles",
        profilePickerLabel: "Profile",
        addProfileButton: "Add profile",
        duplicateProfileButton: "Duplicate profile",
        deleteProfileButton: "Delete profile",
        deleteProfileConfirmFormat: "Delete “%@”?",
        deleteProfileConfirmMessage: "Its actions, shortcut, mouse button and four-finger tap will be removed. This can’t be undone.",
        profileNameLabel: "Profile name",
        profileColorLabel: "Color",
        profileShortcutLabel: "Shortcut",
        profileMouseTriggerLabel: "Mouse button",
        presetGeneral: "General",
        presetMedia: "Media",
        presetTools: "Tools",
        presetWindowLayout: "Window layout",
        presetQuickToggles: "Quick toggles",
        presetBlank: "Blank",
        colorAccent: "Accent",
        colorBlue: "Blue",
        colorPurple: "Purple",
        colorPink: "Pink",
        colorRed: "Red",
        colorOrange: "Orange",
        colorYellow: "Yellow",
        colorGreen: "Green",
        colorMint: "Mint",
        colorCyan: "Cyan",
        colorIndigo: "Indigo",
        colorGraphite: "Graphite",
        fetchFaviconButton: "Fetch Website Icon",
        fetchFaviconDisclaimer: "Connects to the website once to download its icon. Saved locally.",
        fetchFaviconLoading: "Fetching icon…",
        fetchFaviconSuccess: "Icon downloaded",
        fetchFaviconError: "Could not find a website icon",
        mouseTriggerRequirement: "Only extra mouse buttons work here. With a mouse without extra buttons, use the keyboard shortcut above. With a trackpad, you can also use the four-finger tap below.",
        canvasHint: "Click a button to choose what it starts, or to remove it. Drag a button to move it.",
        resetActionsButton: "Reset",
        resetActionsConfirm: "Reset actions",
        resetActionsConfirmMessage: "Restore the default actions for this profile? Custom actions will be replaced.",
        showListButton: "Show as list",
        hideListButton: "Hide list",
        trackpadTapLabel: "Open with a four-finger tap",
        trackpadTapConflict: "Middle click already uses the four-finger tap, so the tap does not open this wheel.",
        profileNoTrigger: "Picking a profile here only edits it. Give this one a shortcut, a mouse button or the four-finger tap below to open it."
    )

    static let fr = RadialMenuFeatureStrings(
        pageTitle: "Menu radial",
        hubDescription: "Ouvre une roue avec vos actions préférées autour du pointeur",
        enableLabel: "Utiliser le menu radial",
        enableCaption: "Maintenez le raccourci, visez une action et relâchez. Un appui bref garde la roue ouverte.",
        positionLabel: "S’ouvre",
        positionPointer: "Au pointeur",
        positionCenter: "Au centre de l’écran",
        tryButton: "Essayer",
        actionsHeader: "Actions",
        addButton: "Ajouter une action",
        limitCaption: "Une roue contient jusqu’à 12 actions.",
        emptyCaption: "Aucune action ici pour le moment.",
        backButton: "Retour",
        editActionsButton: "Modifier les actions",
        nameLabel: "Nom",
        automaticLabel: "Automatique",
        iconLabel: "Icône",
        actionLabel: "Action",
        kindApp: "Ouvrir une app",
        kindFile: "Ouvrir un fichier ou un dossier",
        kindURL: "Ouvrir un lien",
        kindShortcut: "Appuyer sur un raccourci",
        kindTool: "Outil Mac Island",
        kindMedia: "Contrôle multimédia",
        kindSubmenu: "Sous-menu",
        chooseButton: "Choisir…",
        urlPlaceholder: "exemple.fr",
        urlInvalid: "Saisissez un lien valide.",
        toolLabel: "Outil",
        mediaLabel: "Contrôle",
        mediaPlayPause: "Lecture ou pause",
        mediaPrevious: "Piste précédente",
        mediaNext: "Piste suivante",
        mediaNowPlaying: "À l’écoute",
        mediaNothingPlaying: "Aucune lecture",
        mediaOpenAppFormat: "Ouvrir %@",
        submenuCaption: "Ouvre une seconde roue avec ses propres actions.",
        saveButton: "Enregistrer",
        deleteButton: "Supprimer",
        permissionCaption: "Les actions de touches et le bouton latéral demandent l’autorisation Accessibilité.",
        manageButton: "Gérer le menu",
        panelCaption: "Vos actions préférées sur une roue",
        mouseTriggerLabel: "Bouton de la souris",
        mouseTriggerOff: "Désactivé",
        mouseTriggerBack: "Bouton latéral précédent",
        mouseTriggerForward: "Bouton latéral suivant",
        mouseTriggerWarning: "Tant que c’est activé, ce bouton ne fait plus précédent ou suivant dans les apps. Si vous naviguez avec, laissez désactivé.",
        buttonTestLabel: "Test du bouton",
        buttonTestWaiting: "Appuyez sur le bouton",
        buttonTestSeen: "Mac Island voit ce bouton",
        buttonTestOther: "C’était un autre bouton",
        buttonTestBlind: "Mac Island ne peut pas observer la souris pour le moment",
        buttonTestHint: "Si rien ne s’allume, macOS ne transmet pas ce bouton aux apps. Les souris livrées avec leur propre logiciel changent souvent les boutons latéraux. Rétablissez-le là-bas, ou donnez une combinaison de touches au bouton et utilisez cette combinaison ci-dessus.",
        activationModeLabel: "Comportement d’ouverture",
        activationModePressOrHold: "Appuyer ou maintenir",
        activationModePress: "Appuyer pour ouvrir",
        activationModeHold: "Maintenir pour choisir",
        activationModeCaption: "Appuyer ou maintenir conserve le geste adaptatif actuel. Appuyer laisse la roue ouverte\u{00A0}; maintenir lance l’action surlignée au relâchement.",
        profilesHeader: "Profils",
        profilePickerLabel: "Profil",
        addProfileButton: "Ajouter un profil",
        duplicateProfileButton: "Dupliquer le profil",
        deleteProfileButton: "Supprimer le profil",
        deleteProfileConfirmFormat: "Supprimer «\u{00A0}%@\u{00A0}»\u{00A0}?",
        deleteProfileConfirmMessage: "Les actions, le raccourci, le bouton de la souris et le toucher à quatre doigts de ce profil seront supprimés. Cette action est irréversible.",
        profileNameLabel: "Nom du profil",
        profileColorLabel: "Couleur",
        profileShortcutLabel: "Raccourci",
        profileMouseTriggerLabel: "Bouton de la souris",
        presetGeneral: "Général",
        presetMedia: "Médias",
        presetTools: "Outils",
        presetWindowLayout: "Disposition des fenêtres",
        presetQuickToggles: "Boutons rapides",
        presetBlank: "Vierge",
        colorAccent: "Accent",
        colorBlue: "Bleu",
        colorPurple: "Violet",
        colorPink: "Rose",
        colorRed: "Rouge",
        colorOrange: "Orange",
        colorYellow: "Jaune",
        colorGreen: "Vert",
        colorMint: "Menthe",
        colorCyan: "Cyan",
        colorIndigo: "Indigo",
        colorGraphite: "Graphite",
        fetchFaviconButton: "Récupérer l’icône du site",
        fetchFaviconDisclaimer: "Se connecte au site web une seule fois pour télécharger l’icône. Enregistrée localement.",
        fetchFaviconLoading: "Récupération de l’icône…",
        fetchFaviconSuccess: "Icône téléchargée",
        fetchFaviconError: "Impossible de trouver l’icône du site web",
        mouseTriggerRequirement: "Seuls les boutons supplémentaires de la souris fonctionnent ici. Avec une souris sans boutons supplémentaires, utilisez le raccourci clavier ci-dessus. Avec un trackpad, vous pouvez aussi utiliser le toucher à quatre doigts ci-dessous.",
        canvasHint: "Cliquez sur un bouton pour choisir son action ou le retirer. Faites glisser pour le déplacer.",
        resetActionsButton: "Réinitialiser",
        resetActionsConfirm: "Réinitialiser les actions",
        resetActionsConfirmMessage: "Restaurer les actions par défaut de ce profil\u{00A0}? Les actions personnalisées seront remplacées.",
        showListButton: "Afficher sous forme de liste",
        hideListButton: "Masquer la liste",
        trackpadTapLabel: "Ouvrir d’un toucher à quatre doigts",
        trackpadTapConflict: "Le clic du milieu utilise déjà le toucher à quatre doigts, donc ce toucher n’ouvre pas cette roue.",
        profileNoTrigger: "Choisir un profil ici sert seulement à le modifier. Donnez à celui-ci un raccourci, un bouton de la souris ou le toucher à quatre doigts ci-dessous pour l’ouvrir."
    )

}
