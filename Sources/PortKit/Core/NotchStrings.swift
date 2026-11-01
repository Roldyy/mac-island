// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchStrings {
    let title: String
    let combineActivities: String
    let enable: String
    let description: String
    let menuBarAccessHint: String
    let display: String
    let automatic: String
    let builtIn: String
    let mainDisplay: String
    let followPointer: String
    let allDisplays: String
    let hover: String
    let modules: String
    let events: String
    let clipboardActivity: String
    let captureActivity: String
    let privacy: String
    let open: String
    let collapse: String
    let pin: String
    let unpin: String
    let panel: String
    let dropHint: String
    let empty: String
    let volume: String
    let inputSource: String
    let brightness: String
    let battery: String
    let onBattery: String
    let charging: String
    let charged: String
    let lowBattery: String
    let controls: String
    let system: String
    let disabled: String
    let files: String
    let hideInFullscreen: String
    let showInCaptures: String
    let clipboardWindow: String
    let tools: String
    let size: String
    let showOutline: String
    let compact: String
    let spacious: String
    let hoverExpand: String
    let shelfWindow: String
    let dragReveal: String
    let captureControls: String
    let quickPanel: String
    let appPanel: String
    let idleContent: String
    let idleNone: String
    let coverMenus: String
    let coverMenusHint: String
    let controlShortcuts: String
    let activity: String
    let playingMusic: String
    let custom: String
    let width: String
    let maximumHeight: String
    let sizeHint: String
    let cameraFit: String
    let height: String
    let cameraFitHint: String
    let hideMenuBarGap: String
    let hideMenuBarGapHint: String
    let withoutNotch: String
    let capsuleShape: String
    let notchShape: String
    let withoutNotchUnreached: String
    let showOnAllDisplays: String
    let capsuleFit: String
    let fromTop: String
    let capsuleFitHint: String
    let hapticFeedback: String
    let hapticHint: String
    let playbackPosition: String
    let musicHint: String
    let music: String
    let captures: String
    let newTrack: String
    let customizeTools: String
    let switchSection: String
    let sectionsTitle: String
    let searchSections: String
    let sectionKeyboardHint: String
    let quickAccessLeft: String
    let quickAccessRight: String
    let translucentBackground: String
    let translucentBackgroundHint: String
    let translucentBackgroundGlassHint: String
}

extension FeatureStrings {
    static func notch(_ language: AppLanguage) -> NotchStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension NotchStrings {
    static let enUS = NotchStrings(
        title: "Dynamic Island",
        combineActivities: "Combine",
        enable: "Enable Dynamic Island",
        description: "Your music, controls and everyday tools, together at the top of your screen. Optional. Turn it off to keep using the separate panels.",
        menuBarAccessHint: "Allow Accessibility so Dynamic Island can appear on this display without covering the menus.",
        display: "Display",
        automatic: "Automatic",
        builtIn: "Built-in display",
        mainDisplay: "Main display",
        followPointer: "Follow pointer",
        allDisplays: "All displays",
        hover: "Open when the pointer rests on the Dynamic Island",
        modules: "What appears",
        events: "More options",
        clipboardActivity: "Notify when something is copied",
        captureActivity: "Show screenshot previews here",
        privacy: "Copied content stays private until you open the clipboard. These options follow the original feature’s settings.",
        open: "Open Dynamic Island",
        collapse: "Collapse",
        pin: "Keep open",
        unpin: "Allow automatic closing",
        panel: "Open app panel",
        dropHint: "Drop files here",
        empty: "Choose what appears in Dynamic Island settings.",
        volume: "Volume",
        inputSource: "Input source",
        brightness: "Brightness",
        battery: "Battery",
        onBattery: "On battery",
        charging: "Charging",
        charged: "Fully charged",
        lowBattery: "Low battery",
        controls: "Controls",
        system: "System",
        disabled: "Enable the corresponding feature to use it here.",
        files: "Files",
        hideInFullscreen: "Hide content in full screen",
        showInCaptures: "Show in screenshots and videos",
        clipboardWindow: "Open clipboard history in the Dynamic Island",
        tools: "Tools",
        size: "Size",
        showOutline: "Show outline",
        compact: "Compact",
        spacious: "Spacious",
        hoverExpand: "Expand fully on hover",
        shelfWindow: "Open the file shelf in the Dynamic Island",
        dragReveal: "Show a drop target while dragging",
        captureControls: "Show screen capture controls in the Dynamic Island",
        quickPanel: "Open the quick panel in the Dynamic Island",
        appPanel: "Open the app panel in the Dynamic Island",
        idleContent: "While inactive",
        idleNone: "Nothing",
        coverMenus: "Show over the menus",
        coverMenusHint: "Keeps the timer, music and other compact activity on screen when the menu bar has no room, covering the menus beside the camera.",
        controlShortcuts: "Controls and shortcuts",
        activity: "Activity",
        playingMusic: "Show music while playing",
        custom: "Custom",
        width: "Width",
        maximumHeight: "Maximum height",
        sizeHint: "Controls stay compact. Longer lists use up to this height.",
        cameraFit: "Notch fit",
        height: "Height",
        cameraFitHint: "If an edge of the notch shows around Dynamic Island, adjust these values until it disappears.",
        hideMenuBarGap: "Hide gap below notch",
        hideMenuBarGapHint: "Extends Dynamic Island to the bottom of the menu bar to hide the thin strip below the notch.",
        withoutNotch: "Displays without a notch",
        capsuleShape: "Capsule",
        notchShape: "Notch",
        withoutNotchUnreached: "With the Display chosen on the Behavior tab, Dynamic Island doesn’t appear on these displays.",
        showOnAllDisplays: "Show on all displays",
        capsuleFit: "Capsule fit",
        fromTop: "Distance from top",
        capsuleFitHint: "Resizes the capsule and lowers it from the top of the screen on displays without a notch.",
        hapticFeedback: "Haptic feedback",
        hapticHint: "Gentle taps when opening, switching sections or adjusting timer minutes, on a compatible trackpad.",
        playbackPosition: "Playback position",
        musicHint: "Your music and playback controls appear here.",
        music: "Music",
        captures: "Captures",
        newTrack: "New track",
        customizeTools: "Customize tools",
        switchSection: "Switch section",
        sectionsTitle: "Explore",
        searchSections: "Find a section",
        sectionKeyboardHint: "Use the arrow keys, then press Return",
        quickAccessLeft: "Left",
        quickAccessRight: "Right",
        translucentBackground: "Translucent background",
        translucentBackgroundHint: "When open, Dynamic Island blurs what is behind it with the system’s own material.",
        translucentBackgroundGlassHint: "Liquid Glass is on, so Dynamic Island uses it instead."
    )

    static let fr = NotchStrings(
        title: "Dynamic Island",
        combineActivities: "Combiner",
        enable: "Activer Dynamic Island",
        description: "Votre musique, vos commandes et vos outils du quotidien, réunis en haut de l’écran. Facultatif. Désactivez cette option pour continuer à utiliser les panneaux séparés.",
        menuBarAccessHint: "Autorisez l’accessibilité pour afficher Dynamic Island sur cet écran sans masquer les menus.",
        display: "Écran",
        automatic: "Automatique",
        builtIn: "Écran intégré",
        mainDisplay: "Écran principal",
        followPointer: "Suivre le pointeur",
        allDisplays: "Tous les écrans",
        hover: "Ouvrir lorsque le pointeur reste sur l’encoche",
        modules: "Contenu affiché",
        events: "Plus d’options",
        clipboardActivity: "Signaler les nouvelles copies",
        captureActivity: "Afficher les aperçus de captures ici",
        privacy: "Le contenu copié reste privé jusqu’à l’ouverture de l’historique. Ces options respectent les réglages de chaque fonction.",
        open: "Ouvrir Dynamic Island",
        collapse: "Réduire",
        pin: "Garder ouvert",
        unpin: "Autoriser la fermeture automatique",
        panel: "Ouvrir le panneau de l’app",
        dropHint: "Déposez des fichiers ici",
        empty: "Choisissez le contenu dans les réglages de Dynamic Island.",
        volume: "Volume",
        inputSource: "Source de saisie",
        brightness: "Luminosité",
        battery: "Batterie",
        onBattery: "Sur batterie",
        charging: "En charge",
        charged: "Charge complète",
        lowBattery: "Batterie faible",
        controls: "Commandes",
        system: "Système",
        disabled: "Activez la fonction correspondante pour l’utiliser ici.",
        files: "Fichiers",
        hideInFullscreen: "Masquer le contenu en plein écran",
        showInCaptures: "Afficher dans les captures d’écran et les vidéos",
        clipboardWindow: "Ouvrir l’historique du presse-papiers dans l’encoche",
        tools: "Outils",
        size: "Taille",
        showOutline: "Afficher le contour",
        compact: "Compacte",
        spacious: "Spacieuse",
        hoverExpand: "Déployer au survol",
        shelfWindow: "Ouvrir la zone de fichiers dans le Dynamic Island",
        dragReveal: "Afficher une zone de dépôt pendant le glissement",
        captureControls: "Afficher les commandes de capture dans le Dynamic Island",
        quickPanel: "Ouvrir le panneau rapide dans le Dynamic Island",
        appPanel: "Ouvrir le panneau de l’application dans le Dynamic Island",
        idleContent: "Au repos",
        idleNone: "Rien",
        coverMenus: "Afficher par-dessus les menus",
        coverMenusHint: "Garde le minuteur, la musique et les autres activités compactes à l’écran quand la barre des menus manque de place, en masquant les menus à côté de la caméra.",
        controlShortcuts: "Commandes et raccourcis",
        activity: "Activité",
        playingMusic: "Afficher la musique pendant la lecture",
        custom: "Personnalisé",
        width: "Largeur",
        maximumHeight: "Hauteur maximale",
        sizeHint: "Les commandes restent compactes. Les longues listes utilisent au plus cette hauteur.",
        cameraFit: "Ajustement à l’encoche",
        height: "Hauteur",
        cameraFitHint: "Si un bord de l’encoche apparaît autour de Dynamic Island, modifiez ces valeurs jusqu’à ce qu’il disparaisse.",
        hideMenuBarGap: "Masquer l’espace sous l’encoche",
        hideMenuBarGapHint: "Étend Dynamic Island jusqu’au bas de la barre des menus pour masquer la fine bande sous l’encoche.",
        withoutNotch: "Écrans sans encoche",
        capsuleShape: "Capsule",
        notchShape: "Encoche",
        withoutNotchUnreached: "Avec l’écran choisi dans l’onglet Comportement, Dynamic Island n’apparaît pas sur ces écrans.",
        showOnAllDisplays: "Afficher sur tous les écrans",
        capsuleFit: "Ajustement de la capsule",
        fromTop: "Distance du haut",
        capsuleFitHint: "Modifie la taille de la capsule et l’éloigne du haut de l’écran sur les écrans sans encoche.",
        hapticFeedback: "Retour haptique",
        hapticHint: "De légères impulsions à l’ouverture, au changement de rubrique ou au réglage des minutes du minuteur, sur un trackpad compatible.",
        playbackPosition: "Position de lecture",
        musicHint: "Votre musique et ses commandes apparaissent ici.",
        music: "Musique",
        captures: "Captures",
        newTrack: "Nouveau morceau",
        customizeTools: "Personnaliser les outils",
        switchSection: "Changer de section",
        sectionsTitle: "Explorer",
        searchSections: "Rechercher une section",
        sectionKeyboardHint: "Utilisez les flèches, puis appuyez sur Retour",
        quickAccessLeft: "Gauche",
        quickAccessRight: "Droite",
        translucentBackground: "Fond translucide",
        translucentBackgroundHint: "Ouverte, Dynamic Island floute ce qui se trouve derrière avec le matériau du système.",
        translucentBackgroundGlassHint: "Liquid Glass est activé, Dynamic Island l’utilise donc à la place."
    )

}
