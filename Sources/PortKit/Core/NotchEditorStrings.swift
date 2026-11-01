// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchEditorStrings {
    let layout: String
    let content: String
    let activity: String
    let behavior: String
    let layoutHint: String
    let addButton: String
    let editButton: String
    let removeButton: String
    let buttonName: String
    let position: String
    let bottom: String
    let sectionActions: String
    let quickActions: String
    let findAction: String
    let reorderHint: String
    let opening: String
    let clickOpen: String
    let hoverPreview: String
    let hoverExpand: String
    let hiddenUntilHover: String
    let hiddenShowsActivity: String
    let hiddenShowsActivityHint: String
    let resting: String
    let destinations: String
    let separate: String
    let feedback: String
    let privacy: String
    let reopening: String
    let lastPage: String
    let openActivity: String
    let openActivityHint: String
    let activationTime: String
    let activationTimeHint: String
    let activationTimeFormat: String
    let closeTime: String
    let closeTimeHint: String
    let enableFeatureFormat: String
    let enableSettingFormat: String
    let showPageFormat: String
    let keyboardLightUnavailable: String
    let appPanelHint: String
    let hideMenuBarIcon: String
    let hideMenuBarIconHint: String
    let sections: String
    let sectionsHint: String
    let preview: String
    let hiddenInIsland: String
    let openFeatures: String
    let cameraPreview: String
    let noOptions: String
    let controlsSummary: String
    let mixerSummary: String
    let musicSummary: String
    let clipboardSummary: String
    let capturesSummary: String
    let filesSummary: String
    let systemSummary: String
    let toolsSummary: String
    let calendarSummary: String
    let notificationsSummary: String
    let timerSummary: String
    let cameraSummary: String
    let downloadsSummary: String
    let scratchpadSummary: String
    let agentsSummary: String
    let watchSummary: String

    func enableFeature(_ title: String) -> String { String(format: enableFeatureFormat, title) }
    func enableSetting(_ title: String) -> String { String(format: enableSettingFormat, title) }
    func showPage(_ title: String) -> String { String(format: showPageFormat, title) }

    /// One line on what a section of the island shows.
    func summary(_ module: NotchModule) -> String {
        switch module {
        case .controls: return controlsSummary
        case .mixer: return mixerSummary
        case .music: return musicSummary
        case .clipboard: return clipboardSummary
        case .captures: return capturesSummary
        case .files: return filesSummary
        case .system: return systemSummary
        case .tools: return toolsSummary
        case .calendar: return calendarSummary
        case .notifications: return notificationsSummary
        case .timer: return timerSummary
        case .camera: return cameraSummary
        case .downloads: return downloadsSummary
        case .scratchpad: return scratchpadSummary
        case .agents: return agentsSummary
        case .watch: return watchSummary
        }
    }
}

extension FeatureStrings {
    static func notchEditor(_ language: AppLanguage) -> NotchEditorStrings {
        switch language {
        case .enUS: return NotchEditorStrings(
            layout: "Layout",
            content: "Content",
            activity: "Activity",
            behavior: "Behavior",
            layoutHint: "Click + to add a button. Drag buttons around the island. Click a button to edit it.",
            addButton: "Add button",
            editButton: "Edit button",
            removeButton: "Remove button",
            buttonName: "Name",
            position: "Position",
            bottom: "Bottom",
            sectionActions: "Open a section",
            quickActions: "Quick actions",
            findAction: "Find an action",
            reorderHint: "Drag to reorder. Click the checkmark to show or hide.",
            opening: "Opening",
            clickOpen: "Click to open",
            hoverPreview: "Preview on hover",
            hoverExpand: "Expand on hover",
            hiddenUntilHover: "Hidden until hover",
            hiddenShowsActivity: "Show activity and indicators",
            hiddenShowsActivityHint: "Comes into view while an activity runs or an indicator shows, then hides again.",
            resting: "At rest",
            destinations: "Where things open",
            separate: "Separate window",
            feedback: "Indicators",
            privacy: "Privacy",
            reopening: "When reopening",
            lastPage: "Last page",
            openActivity: "Open the visible activity",
            openActivityHint: "When the closed island shows music, a timer or another activity, it opens on that page instead.",
            activationTime: "Activation time",
            activationTimeHint: "Keep the pointer over the island for this long to open it.",
            activationTimeFormat: "%.2f s",
            closeTime: "Closing time",
            closeTimeHint: "Wait this long after the pointer leaves the island before closing it.",
            enableFeatureFormat: "Enable “%@” in Features.",
            enableSettingFormat: "Enable “%@” in its settings.",
            showPageFormat: "Show “%@” on the Content tab.",
            keyboardLightUnavailable: "Keyboard backlight control is unavailable on this Mac.",
            appPanelHint: "Choose where clicking the Mac Island menu bar icon opens the app panel, on any display.",
            hideMenuBarIcon: "Hide the menu bar icon",
            hideMenuBarIconHint: "Settings and the app panel open from Dynamic Island. The icon returns when the island is off or hidden in full screen, or when an update is ready or the microphone is muted.",
            sections: "Sections",
            sectionsHint: "Drag to reorder. Uncheck a section to hide it from the island.",
            preview: "Preview",
            hiddenInIsland: "Hidden from the island",
            openFeatures: "Open Features",
            cameraPreview: "The camera turns on only in the island.",
            noOptions: "This section has no options.",
            controlsSummary: "Playback, volume, brightness and your shortcuts.",
            mixerSummary: "The volume of each app, and where sound plays.",
            musicSummary: "The song playing now, with its controls.",
            clipboardSummary: "What you copied recently, ready to paste again.",
            capturesSummary: "Your latest screenshots and recordings.",
            filesSummary: "A shelf for the files you drop on the island.",
            systemSummary: "CPU, memory, disk, network and battery at a glance.",
            toolsSummary: "Tools and utilities, one click away.",
            calendarSummary: "Today’s events and the month ahead.",
            notificationsSummary: "Your Mac’s notifications, kept in the island.",
            timerSummary: "Timer, Pomodoro and stopwatch.",
            cameraSummary: "A mirror to check yourself before a call.",
            downloadsSummary: "Downloads in progress and just finished.",
            scratchpadSummary: "Quick notes that save by themselves.",
            agentsSummary: "Claude Code, Codex, OpenCode and GitHub Copilot usage, limits and costs.",
            watchSummary: "Any part of a window, read live, with an alert when it changes."
        )
        default: return NotchEditorStrings(
            layout: "Disposition",
            content: "Contenu",
            activity: "Activité",
            behavior: "Comportement",
            layoutHint: "Cliquez sur + pour ajouter un bouton. Faites glisser les boutons autour de l’îlot. Cliquez pour modifier.",
            addButton: "Ajouter un bouton",
            editButton: "Modifier le bouton",
            removeButton: "Retirer le bouton",
            buttonName: "Nom",
            position: "Position",
            bottom: "En bas",
            sectionActions: "Ouvrir une section",
            quickActions: "Actions rapides",
            findAction: "Rechercher une action",
            reorderHint: "Glissez pour réordonner. Cliquez sur la coche pour afficher ou masquer.",
            opening: "Ouverture",
            clickOpen: "Ouvrir au clic",
            hoverPreview: "Aperçu au survol",
            hoverExpand: "Déployer au survol",
            hiddenUntilHover: "Masquer jusqu’au survol",
            hiddenShowsActivity: "Afficher l’activité et les indicateurs",
            hiddenShowsActivityHint: "Apparaît pendant une activité ou tant qu’un indicateur s’affiche, puis se masque à nouveau.",
            resting: "Au repos",
            destinations: "Lieu d’ouverture",
            separate: "Fenêtre séparée",
            feedback: "Indicateurs",
            privacy: "Confidentialité",
            reopening: "À la réouverture",
            lastPage: "Dernière page",
            openActivity: "Ouvrir l’activité visible",
            openActivityHint: "Quand l’île fermée affiche de la musique, un minuteur ou une autre activité, elle s’ouvre plutôt sur la page de cette activité.",
            activationTime: "Délai d’activation",
            activationTimeHint: "Laissez le pointeur sur l’île pendant cette durée pour l’ouvrir.",
            activationTimeFormat: "%.2f s",
            closeTime: "Délai de fermeture",
            closeTimeHint: "Après que le pointeur a quitté l’île, attendre cette durée avant de la fermer.",
            enableFeatureFormat: "Activez « %@ » dans Fonctionnalités.",
            enableSettingFormat: "Activez « %@ » dans ses réglages.",
            showPageFormat: "Affichez « %@ » dans l’onglet Contenu.",
            keyboardLightUnavailable: "Le contrôle du rétroéclairage du clavier est indisponible sur ce Mac.",
            appPanelHint: "Choisissez où un clic sur l’icône Mac Island de la barre des menus ouvre le panneau, sur tout écran.",
            hideMenuBarIcon: "Masquer l’icône de la barre des menus",
            hideMenuBarIconHint: "Les Réglages et le panneau de l’app s’ouvrent depuis Dynamic Island. L’icône revient quand Dynamic Island est désactivée ou masquée en plein écran, ou quand une mise à jour est prête ou que le micro est coupé.",
            sections: "Sections",
            sectionsHint: "Glissez pour réordonner. Décochez une section pour la masquer de l’îlot.",
            preview: "Aperçu",
            hiddenInIsland: "Masquée dans l’îlot",
            openFeatures: "Ouvrir Fonctionnalités",
            cameraPreview: "La caméra ne s’allume que dans l’îlot.",
            noOptions: "Cette section n’a pas d’options.",
            controlsSummary: "Lecture, volume, luminosité et vos raccourcis.",
            mixerSummary: "Le volume de chaque app et la sortie du son.",
            musicSummary: "Le morceau en cours, avec ses commandes.",
            clipboardSummary: "Ce que vous avez copié récemment, prêt à être recollé.",
            capturesSummary: "Vos dernières captures d’écran et vidéos.",
            filesSummary: "Une étagère pour les fichiers déposés sur l’îlot.",
            systemSummary: "Processeur, mémoire, disque, réseau et batterie en un coup d’œil.",
            toolsSummary: "Outils et utilitaires à portée de clic.",
            calendarSummary: "Les événements du jour et le mois entier.",
            notificationsSummary: "Les notifications de votre Mac, réunies dans l’îlot.",
            timerSummary: "Minuteur, Pomodoro et chronomètre.",
            cameraSummary: "Un miroir pour vous voir avant un appel.",
            downloadsSummary: "Les téléchargements en cours et ceux qui viennent de finir.",
            scratchpadSummary: "Des notes rapides qui s’enregistrent seules.",
            agentsSummary: "Utilisation, limites et coûts de Claude Code, Codex, OpenCode et GitHub Copilot.",
            watchSummary: "N’importe quelle partie d’une fenêtre, lue en direct, avec une alerte quand elle change."
        )
        }
    }
}
