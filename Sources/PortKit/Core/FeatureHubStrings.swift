// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Strings for the Features hub and its permissions portal. Same contract as
/// the other FeatureStrings structs: memberwise init with labeled arguments
/// in declaration order, one static per language, all in this file.
struct FeatureHubStrings {
    // Page chrome
    let pageTitle: String
    let intro: String
    let tabFeatures: String
    let tabPermissions: String
    let activeCountFormat: String      // "%1$d of %2$d features on"
    let monitorAllOffNote: String
    let titleDockClick: String
    let titleMouseNavigation: String
    let titleMusicBlock: String
    let titleAudioPriority: String
    // Group headers
    let groupWindowsDock: String
    let groupMouseKeyboard: String
    let groupClipboardFiles: String
    let groupSound: String
    let groupEnergyDisplay: String
    let groupTools: String
    let groupMonitor: String
    let experimentalBadge: String
    // Permissions portal
    let permissionsIntro: String
    let usedByFormat: String           // "Used by %@"
    let usedByNone: String
    let unusedBanner: String
    let statusGranted: String
    let statusMissing: String
    let statusUnknown: String
    let requestButton: String
    let openSystemSettings: String
    let permAccessibility: String
    let permScreenRecording: String
    let permFullDisk: String
    let permFilesAndFolders: String
    let permNotifications: String
    let permAutomationFinder: String
    let permAutomationTerminal: String
    let permAudioCapture: String
    let explainAccessibility: String
    let explainScreenRecording: String
    let explainFullDisk: String
    let explainFilesAndFolders: String
    let explainNotifications: String
    let explainAutomationFinder: String
    let explainAutomationTerminal: String
    let explainAudioCapture: String
    // One-line feature descriptions
    let descSwitcher: String
    let descDockPreview: String
    let descDockClick: String
    let descWindowMaximizer: String
    let descWindowLayout: String
    let descAutoQuit: String
    let descScrollInverter: String
    let descSmoothScroll: String
    let descMouseNavigation: String
    let descMiddleClick: String
    let descKeyboardDebounce: String
    let descClipboardHistory: String
    let descPastePlain: String
    let descFinderCutPaste: String
    let descShelf: String
    let descURLCleaner: String
    let descMixer: String
    let descSoundOutputSwitcher: String
    let descAudioPriority: String
    let descMicMute: String
    let descMusicBlock: String
    let descKeepAwake: String
    let descExtraBrightness: String
    let descQuickLauncher: String
    let descColorPicker: String
    let descScreenOCR: String
    let descCleaningMode: String
    let descMediaTools: String
    let descCleaner: String
    let descUninstaller: String
    let descHomebrew: String
    let descMonitorCPU: String
    let descMonitorGPU: String
    let descMonitorMemory: String
    let descMonitorNetwork: String
    let descMonitorDisk: String
    let descMonitorPower: String
    // Install metaphor and the restart-to-unload card
    let footerNote: String
    let restartNote: String
    let restartButton: String
    let installButton: String
    let uninstallButton: String
    let installAllButton: String
    let uninstallAllButton: String
    let presetsTitle: String
    let presetsCaption: String
    let presetEssentialName: String
    let presetEssentialDesc: String
    let presetWindowsName: String
    let presetWindowsDesc: String
    let presetBatteryName: String
    let presetBatteryDesc: String
    let presetApplyButton: String
    let presetConfirmFormat: String
    let presetConfirmApply: String
    let presetConfirmCancel: String
    let energyIdle: String
    let energyMouse: String
    let energyPointer: String
    let energyKeyboard: String
    let energyInputs: String
    let energyPeriodic: String
    let energyHelp: String
    let explainAppManagement: String
    let onboardingSelectedPermissionsTitle: String
    let onboardingNoSelectedPermissions: String
    let onboardingOtherPermissionsTitle: String
    let onboardingOtherPermissionsCaption: String
    // Uninstalling the Dynamic Island while extensions of it are installed
    let notchUninstallTitle: String
    let notchUninstallMessageFormat: String   // "…: %@. …", the installed extensions' names
    let notchUninstallWithExtensions: String
    let notchUninstallKeepExtensions: String
    // Installed features never turned on, offered for uninstalling together
    let neverUsedTitle: String
    let neverUsedMessageFormat: String   // "…: %@. …" with the feature names
    let neverUsedUninstall: String
    let neverUsedKeep: String
}

extension FeatureStrings {
    static func hub(_ language: AppLanguage) -> FeatureHubStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension FeatureHubStrings {
}

extension FeatureHubStrings {
    static let enUS = FeatureHubStrings(
        pageTitle: "Features",
        intro: "Install only what you use. Whatever you uninstall disappears from the whole app and stops loading.",
        tabFeatures: "Features",
        tabPermissions: "Permissions",
        activeCountFormat: "%1$d of %2$d features installed",
        monitorAllOffNote: "With everything off, the Monitor leaves the panel and the menu bar.",
        titleDockClick: "Dock clicks",
        titleMouseNavigation: "Side buttons",
        titleMusicBlock: "Music app blocker",
         titleAudioPriority: "Audio device priority",
        groupWindowsDock: "Windows and Dock",
        groupMouseKeyboard: "Mouse and keyboard",
        groupClipboardFiles: "Clipboard and files",
        groupSound: "Sound",
        groupEnergyDisplay: "Energy and display",
        groupTools: "Tools",
        groupMonitor: "System monitor",
        experimentalBadge: "Experimental",
        permissionsIntro: "What each permission does and which features use it. Other access is requested only when you use it.",
        usedByFormat: "Used by %@",
        usedByNone: "Nothing that is on uses this permission right now.",
        unusedBanner: "You granted this permission, but nothing that is on needs it. If you like, revoke it in System Settings.",
        statusGranted: "Granted",
        statusMissing: "Not granted",
        statusUnknown: "The app can’t check this one",
        requestButton: "Request",
        openSystemSettings: "Open System Settings",
        permAccessibility: "Accessibility",
        permScreenRecording: "Screen Recording",
        permFullDisk: "Full Disk Access",
        permFilesAndFolders: "Files & Folders",
        permNotifications: "Notifications",
        permAutomationFinder: "Finder automation",
        permAutomationTerminal: "Terminal automation",
        permAudioCapture: "App audio",
        explainAccessibility: "Lets features react to clicks and keys, and move windows.",
        explainScreenRecording: "Lets features show window thumbnails and read text on screen.",
        explainFullDisk: "Lets the cleaner and the uninstaller find leftover files everywhere.",
        explainFilesAndFolders: "Lets WhatsApp downloads cleanup and the experimental organizer inspect your Downloads folder.",
        explainNotifications: "Lets the app notify you about alerts you turned on.",
        explainAutomationFinder: "Lets the app ask Finder to move files for you.",
        explainAutomationTerminal: "Lets Homebrew commands open in Terminal.",
        explainAudioCapture: "Lets the mixer adjust each app’s volume, the Dynamic Island bars follow the music and screen recordings include the Mac’s sound.",
        descSwitcher: "Switch apps and windows with previews",
        descDockPreview: "Window previews when hovering the Dock",
        descDockClick: "Click a Dock icon to minimize or cycle windows",
        descWindowMaximizer: "The green button maximizes instead of full screen",
        descWindowLayout: "Arrange windows with shortcuts or edge snapping, then adjust them by dragging",
        descAutoQuit: "Quit apps when their last window closes",
        descScrollInverter: "Invert the mouse wheel direction",
        descSmoothScroll: "Smooth, animated mouse scrolling",
        descMouseNavigation: "Side mouse buttons go back and forward",
        descMiddleClick: "Three finger click acts as a middle click",
        descKeyboardDebounce: "Ignore accidental double key presses",
        descClipboardHistory: "Keep a local history of what you copy",
        descPastePlain: "Paste text without formatting",
        descFinderCutPaste: "Cut and paste files in Finder",
        descShelf: "Drop files on the menu bar to hold them",
        descURLCleaner: "Copied links lose their tracking junk",
        descMixer: "Per-app volume, pinning and custom order",
        descSoundOutputSwitcher: "Cycle sound outputs with a shortcut",
         descAudioPriority: "Automatically use your preferred audio devices",
        descMicMute: "Mute the microphone from anywhere",
        descMusicBlock: "Block music launches from detected media keys",
        descKeepAwake: "Keep the Mac awake on demand",
        descExtraBrightness: "Extra brightness on XDR displays",
        descQuickLauncher: "A floating panel with your favorite tools",
        descColorPicker: "Pick any color on screen",
        descScreenOCR: "Copy text or QR codes from anything on screen",
        descCleaningMode: "Lock keyboard and screen for cleaning",
        descMediaTools: "Compress videos, images and GIFs",
        descCleaner: "Clear caches and junk files",
        descUninstaller: "Remove apps and their leftovers",
        descHomebrew: "Keep Homebrew packages up to date",
        descMonitorCPU: "Processor usage and temperature",
        descMonitorGPU: "Graphics usage and temperature",
        descMonitorMemory: "Memory use and pressure",
        descMonitorNetwork: "Network speed and usage",
        descMonitorDisk: "Disk space and activity",
        descMonitorPower: "Battery, power and charging",
        footerNote: "Uninstalling deletes nothing: the feature just leaves the app and stops loading. Install it again anytime and everything returns as it was.",
        restartNote: "Features uninstalled in this session stay loaded until the app restarts. Restart to unload them from memory now.",
        restartButton: "Restart now",
        installButton: "Install",
        uninstallButton: "Uninstall",
        installAllButton: "Install all",
        uninstallAllButton: "Uninstall all",
        presetsTitle: "Start with a bundle",
        presetsCaption: "One click sets the app up for how you use your Mac. Everything else stays one click away.",
        presetEssentialName: "Essentials",
        presetEssentialDesc: "Volume mixer, system monitor and keep awake.",
        presetWindowsName: "Windows",
        presetWindowsDesc: "Window switcher, window layout and the Dock features.",
        presetBatteryName: "Battery and quiet",
        presetBatteryDesc: "A lean monitor with battery, memory and processor. Nothing listens to input.",
        presetApplyButton: "Apply",
        presetConfirmFormat: "Install the %1$@ bundle and uninstall the rest? Nothing is deleted, and everything comes back with one click.",
        presetConfirmApply: "Apply bundle",
        presetConfirmCancel: "Cancel",
        energyIdle: "Nothing at rest",
        energyMouse: "Listens to the mouse",
        energyPointer: "Listens to pointer input",
        energyKeyboard: "Listens to the keyboard",
        energyInputs: "Listens to mouse and keyboard",
        energyPeriodic: "Checks on an interval",
        energyHelp: "What the feature keeps alive while it is on. Uninstalled features load nothing at all.",
        explainAppManagement: "Lets updates replace or remove apps installed by the package manager.",
        onboardingSelectedPermissionsTitle: "Permissions for your choices",
        onboardingNoSelectedPermissions: "You do not need to grant any permission to finish setup.",
        onboardingOtherPermissionsTitle: "Other permissions",
        onboardingOtherPermissionsCaption: "Optional. Grant these now or later, when a feature needs them.",
        notchUninstallTitle: "Uninstall Dynamic Island",
        notchUninstallMessageFormat: "These extensions only work inside the Dynamic Island: %@. Uninstall them too? Nothing is deleted, and everything comes back with one click.",
        notchUninstallWithExtensions: "Uninstall extensions too",
        notchUninstallKeepExtensions: "Keep extensions",
        neverUsedTitle: "Never turned on",
        neverUsedMessageFormat: "These features are installed but have never been on: %@. Uninstalling them makes the panel and Settings shorter. Nothing is deleted, and each one comes back with one click.",
        neverUsedUninstall: "Uninstall these",
        neverUsedKeep: "Keep them"
    )

    static let fr = FeatureHubStrings(
        pageTitle: "Fonctions",
        intro: "N’installez que ce que vous utilisez. Tout ce qui est désinstallé disparaît de toute l’app et ne se charge plus.",
        tabFeatures: "Fonctions",
        tabPermissions: "Autorisations",
        activeCountFormat: "%1$d fonctions sur %2$d installées",
        monitorAllOffNote: "Tout éteint, le Moniteur disparaît du panneau et de la barre des menus.",
        titleDockClick: "Clics sur le Dock",
        titleMouseNavigation: "Boutons latéraux",
        titleMusicBlock: "Blocage de l’app Musique",
        titleAudioPriority: "Priorité des périphériques audio",
        groupWindowsDock: "Fenêtres et Dock",
        groupMouseKeyboard: "Souris et clavier",
        groupClipboardFiles: "Presse-papiers et fichiers",
        groupSound: "Son",
        groupEnergyDisplay: "Énergie et écran",
        groupTools: "Outils",
        groupMonitor: "Moniteur système",
        experimentalBadge: "Expérimental",
        permissionsIntro: "Ce que fait chaque autorisation et quelles fonctions l’utilisent. Les autres accès ne sont demandés qu’à l’utilisation.",
        usedByFormat: "Utilisée par %@",
        usedByNone: "Rien d’activé n’utilise cette autorisation pour l’instant.",
        unusedBanner: "Vous avez accordé cette autorisation, mais rien d’activé n’en a besoin. Si vous voulez, révoquez-la dans Réglages Système.",
        statusGranted: "Accordée",
        statusMissing: "Non accordée",
        statusUnknown: "L’app ne peut pas vérifier celle-ci",
        requestButton: "Demander",
        openSystemSettings: "Ouvrir Réglages Système",
        permAccessibility: "Accessibilité",
        permScreenRecording: "Enregistrement de l’écran",
        permFullDisk: "Accès complet au disque",
        permFilesAndFolders: "Fichiers et dossiers",
        permNotifications: "Notifications",
        permAutomationFinder: "Automatisation du Finder",
        permAutomationTerminal: "Automatisation du Terminal",
        permAudioCapture: "Audio des apps",
        explainAccessibility: "Permet aux fonctions de réagir aux clics et touches et de déplacer les fenêtres.",
        explainScreenRecording: "Permet d’afficher des aperçus de fenêtres et de lire le texte à l’écran.",
        explainFullDisk: "Permet au nettoyeur et au désinstalleur de trouver les restes partout.",
        explainFilesAndFolders: "Autorise le nettoyage et l’organisateur expérimental WhatsApp à examiner le dossier Téléchargements.",
        explainNotifications: "Permet à l’app de vous prévenir des alertes que vous avez activées.",
        explainAutomationFinder: "Permet à l’app de demander au Finder de déplacer des fichiers pour vous.",
        explainAutomationTerminal: "Permet aux commandes Homebrew de s’ouvrir dans le Terminal.",
        explainAudioCapture: "Permet au mixeur d’ajuster le volume de chaque app, aux barres du Dynamic Island de suivre la musique et aux enregistrements d’écran d’inclure le son du Mac.",
        descSwitcher: "Changez d’app et de fenêtre avec des aperçus",
        descDockPreview: "Aperçus des fenêtres au survol du Dock",
        descDockClick: "Cliquez une icône du Dock pour réduire ou alterner",
        descWindowMaximizer: "Le bouton vert agrandit au lieu du plein écran",
        descWindowLayout: "Organisez les fenêtres avec des raccourcis ou l’ancrage aux bords, puis par glissement",
        descAutoQuit: "Quitte l’app quand sa dernière fenêtre se ferme",
        descScrollInverter: "Inverse le sens de la molette de la souris",
        descSmoothScroll: "Défilement fluide et animé à la souris",
        descMouseNavigation: "Les boutons latéraux vont en arrière et en avant",
        descMiddleClick: "Le clic à trois doigts devient un clic du milieu",
        descKeyboardDebounce: "Ignore les doubles frappes accidentelles",
        descClipboardHistory: "Garde un historique local de vos copies",
        descPastePlain: "Collez du texte sans mise en forme",
        descFinderCutPaste: "Coupez et collez des fichiers dans le Finder",
        descShelf: "Déposez des fichiers sur la barre des menus",
        descURLCleaner: "Les liens copiés perdent leurs traqueurs",
        descMixer: "Volume par app, épinglage et ordre personnalisé",
        descSoundOutputSwitcher: "Changez de sortie audio avec un raccourci",
        descAudioPriority: "Utiliser automatiquement vos périphériques audio préférés",
        descMicMute: "Coupez le micro depuis n’importe où",
        descMusicBlock: "Bloque les ouvertures de musique par des touches multimédias détectées",
        descKeepAwake: "Gardez le Mac éveillé à la demande",
        descExtraBrightness: "Luminosité supplémentaire sur les écrans XDR",
        descQuickLauncher: "Un panneau flottant avec vos outils préférés",
        descColorPicker: "Prélevez n’importe quelle couleur à l’écran",
        descScreenOCR: "Copiez le texte ou les codes QR de tout ce qui s’affiche",
        descCleaningMode: "Verrouille clavier et écran pour le nettoyage",
        descMediaTools: "Compressez vidéos, images et GIF",
        descCleaner: "Nettoyez caches et fichiers inutiles",
        descUninstaller: "Supprimez les apps et leurs restes",
        descHomebrew: "Gardez les paquets Homebrew à jour",
        descMonitorCPU: "Utilisation et température du processeur",
        descMonitorGPU: "Utilisation et température graphique",
        descMonitorMemory: "Utilisation et pression mémoire",
        descMonitorNetwork: "Vitesse et usage du réseau",
        descMonitorDisk: "Espace et activité du disque",
        descMonitorPower: "Batterie, alimentation et charge",
        footerNote: "Désinstaller n’efface rien\u{00A0}: la fonction disparaît simplement de l’app et ne se charge plus. Réinstallez-la quand vous voulez, tout revient comme avant.",
        restartNote: "Les fonctions désinstallées pendant cette session restent chargées jusqu’au redémarrage de l’app. Redémarrez pour les décharger maintenant.",
        restartButton: "Redémarrer maintenant",
        installButton: "Installer",
        uninstallButton: "Désinstaller",
        installAllButton: "Tout installer",
        uninstallAllButton: "Tout désinstaller",
        presetsTitle: "Commencez par un pack",
        presetsCaption: "Un clic règle l’app selon votre façon d’utiliser le Mac. Le reste demeure à un clic.",
        presetEssentialName: "Essentiel",
        presetEssentialDesc: "Mixeur de volume, moniteur système et maintien éveillé.",
        presetWindowsName: "Fenêtres",
        presetWindowsDesc: "Sélecteur de fenêtres, disposition des fenêtres et les fonctions du Dock.",
        presetBatteryName: "Batterie et silence",
        presetBatteryDesc: "Un moniteur léger avec batterie, mémoire et processeur. Rien n’écoute les saisies.",
        presetApplyButton: "Appliquer",
        presetConfirmFormat: "Installer le pack %1$@ et désinstaller le reste\u{00A0}? Rien n’est effacé et tout revient en un clic.",
        presetConfirmApply: "Appliquer le pack",
        presetConfirmCancel: "Annuler",
        energyIdle: "Rien au repos",
        energyMouse: "Écoute la souris",
        energyPointer: "Écoute le pointeur",
        energyKeyboard: "Écoute le clavier",
        energyInputs: "Écoute souris et clavier",
        energyPeriodic: "Vérifie par intervalles",
        energyHelp: "Le coût quand la fonction est active. Désinstallée, elle ne charge rien.",
        explainAppManagement: "Permet aux mises à jour de remplacer ou supprimer les apps installées par le gestionnaire de paquets.",
        onboardingSelectedPermissionsTitle: "Autorisations pour vos choix",
        onboardingNoSelectedPermissions: "Aucune autorisation n’est nécessaire pour terminer la configuration.",
        onboardingOtherPermissionsTitle: "Autres autorisations",
        onboardingOtherPermissionsCaption: "Facultatif. Accordez-les maintenant ou plus tard, lorsqu’une fonction en aura besoin.",
        notchUninstallTitle: "Désinstaller Dynamic Island",
        notchUninstallMessageFormat: "Ces extensions ne fonctionnent que dans Dynamic Island\u{00A0}: %@. Les désinstaller aussi\u{00A0}? Rien n’est effacé et tout revient en un clic.",
        notchUninstallWithExtensions: "Désinstaller aussi les extensions",
        notchUninstallKeepExtensions: "Conserver les extensions",
        neverUsedTitle: "Jamais activées",
        neverUsedMessageFormat: "Ces fonctions sont installées mais n’ont jamais été activées\u{00A0}: %@. Les désinstaller raccourcit le panneau et les Réglages. Rien n’est effacé, et chacune revient en un clic.",
        neverUsedUninstall: "Les désinstaller",
        neverUsedKeep: "Les garder"
    )

}

// Українська.
extension FeatureHubStrings {
}
