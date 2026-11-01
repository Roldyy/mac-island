// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

enum FeatureStrings {
    static func settingsCategories(_ language: AppLanguage) -> SettingsCategoryStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }

    static func clipboard(_ language: AppLanguage) -> ClipboardFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }

    static func windowLayout(_ language: AppLanguage) -> WindowLayoutFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }

    static func monitorAlerts(_ language: AppLanguage) -> MonitorAlertFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }

    static func mixer(_ language: AppLanguage) -> MixerFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }

    static func whatsAppDownloads(_ language: AppLanguage) -> WhatsAppDownloadStrings {
        WhatsAppDownloadStrings.localized(language)
    }
}

struct MixerFeatureStrings {
    let hideInactiveApps: String
    let pin: String
    let unpin: String
    let moveUp: String
    let moveDown: String
    /// The island runs the rows sideways, pinned ones first.
    let pinFirst: String
    let moveLeft: String
    let moveRight: String
    let arrange: String
    let actions: String

    static let enUS = MixerFeatureStrings(hideInactiveApps: "Hide inactive apps", pin: "Pin to Top", unpin: "Unpin", moveUp: "Move Up", moveDown: "Move Down", pinFirst: "Pin to Front", moveLeft: "Move Left", moveRight: "Move Right", arrange: "Hold Command and drag to reorder", actions: "Actions")
    static let fr = MixerFeatureStrings(hideInactiveApps: "Masquer les apps inactives", pin: "Épingler en haut", unpin: "Désépingler", moveUp: "Déplacer vers le haut", moveDown: "Déplacer vers le bas", pinFirst: "Épingler au début", moveLeft: "Déplacer vers la gauche", moveRight: "Déplacer vers la droite", arrange: "Maintenez Command et faites glisser pour réorganiser", actions: "Actions")
}

extension SettingsCategoryStrings {
}

extension ClipboardFeatureStrings {
}

extension WindowLayoutFeatureStrings {
}

extension MonitorAlertFeatureStrings {
}

struct SettingsCategoryStrings {
    let essentials: String
    let windowsControls: String
    let files: String
    let utilities: String
    let app: String
    let appManagement: String

    static let enUS = SettingsCategoryStrings(
        essentials: "Essentials",
        windowsControls: "Window controls",
        files: "Files",
        utilities: "Utilities",
        app: "App",
        appManagement: "App management"
    )

    static let fr = SettingsCategoryStrings(
        essentials: "Essentiel",
        windowsControls: "Fenêtres et contrôles",
        files: "Fichiers",
        utilities: "Utilitaires",
        app: "App",
        appManagement: "Gestion des apps"
    )

}

struct ClipboardFeatureStrings {
    let title: String
    let enable: String
    let caption: String
    let localNote: String
    let skipSensitive: String
    let skipSensitiveCaption: String
    let limit: String
    let limitUnlimited: String
    let showInPanel: String
    let shortcut: String
    let shortcutCaption: String
    let shortcutHint: String
    let clickRowShortcut: String
    let commandClickShortcut: String
    let pinned: String
    let recent: String
    let pin: String
    let unpin: String
    let clearRecent: String
    let clearRecentKeywords: String
    let empty: String
    let disabled: String
    let search: String
    let copy: String
    let copied: String
    let delete: String
    let selectMultiple: String
    let unselectMultiple: String
    let selectShortcutAction: String
    let pasteSelectedFormat: String
    let copySelectedFormat: String
    let clearSelection: String
    let moveUp: String
    let moveDown: String
    let noResults: String
    let active: String
    let includeImagesFiles: String
    let includeImagesFilesCaption: String
    let imageEntryLabel: String
    let fileCountFormat: String
    let pasteImageAsFile: String
    let pasteImageAsFileCaption: String
    let previewLabel: String
    let edit: String
    let cancel: String
    let save: String
    let autoClearEnable: String
    let autoClearSecondsSuffix: String
    let autoClearOnSleep: String
    let autoClearOnDisplaySleep: String
    let autoClearOnScreenLock: String
    let autoClearCaption: String
    let deleteSelectedFormat: String
    let menuBarPreview: String
    let menuBarPreviewCaption: String
    let menuBarPreviewLength: String
    let menuBarPreviewLengthSuffix: String
    let clearRecentConfirmFormat: String
    let clearRecentConfirmMessage: String
    let historyLayout: String
    let historyLayoutCards: String
    let historyLayoutList: String

    static let enUS = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Save clipboard history",
        caption: "Stores copied text so you can reuse it later. Everything stays local and can be cleared anytime.",
        localNote: "Everything stays on this Mac. Very large items are ignored.",
        skipSensitive: "Skip text that looks sensitive",
        skipSensitiveCaption: "May skip ordinary text that resembles passwords or tokens. Content marked as confidential by its source app is always excluded.",
        limit: "Limit",
        limitUnlimited: "Unlimited",
        showInPanel: "Show in panel",
        shortcut: "History shortcut",
        shortcutCaption: "Opens a quick window with search, pinned items and ⌘1 to ⌘9 shortcuts for pasting into the previous app.",
        shortcutHint: "Click a row to paste it into the previous app. ⌘-click selects several; ⌘C copies without pasting.",
        clickRowShortcut: "Click row",
        commandClickShortcut: "⌘ Click",
        pinned: "Pinned",
        recent: "Recent",
        pin: "Pin",
        unpin: "Unpin",
        clearRecent: "Clear unpinned",
        clearRecentKeywords: "Clear recent",
        empty: "No saved text",
        disabled: "Enable history to start saving copied text.",
        search: "Search copied text",
        copy: "Copy",
        copied: "Copied",
        delete: "Delete item",
        selectMultiple: "Add to pile",
        unselectMultiple: "Remove from pile",
        selectShortcutAction: "Select",
        pasteSelectedFormat: "Paste %d",
        copySelectedFormat: "Copy %d",
        clearSelection: "Clear selection",
        moveUp: "Move up",
        moveDown: "Move down",
        noResults: "No results",
        active: "Saving new text",
        includeImagesFiles: "Also save copied images and files",
        includeImagesFilesCaption: "Images join the history and files are remembered as links to their location. Pin and paste them like any text item.",
        imageEntryLabel: "Image",
        fileCountFormat: "%d files",
        pasteImageAsFile: "Paste copied images as files",
        pasteImageAsFileCaption: "When Finder is active, ⌘V saves a copied image as a PNG in the current folder.",
        previewLabel: "Preview",
        edit: "Edit",
        cancel: "Cancel",
        save: "Save",
        autoClearEnable: "Auto clear clipboard with a delay of",
        autoClearSecondsSuffix: "seconds",
        autoClearOnSleep: "Clear clipboard on computer sleep",
        autoClearOnDisplaySleep: "Clear clipboard on display sleep",
        autoClearOnScreenLock: "Clear clipboard on screen lock",
        autoClearCaption: "Clears the system clipboard only. Items already saved stay in the history.",
        deleteSelectedFormat: "Delete %d",
        menuBarPreview: "Show latest copy in the menu bar",
        menuBarPreviewCaption: "Shows a shortened preview of your last copy next to the icon. Click it to open the history.",
        menuBarPreviewLength: "Preview length",
        menuBarPreviewLengthSuffix: "characters",
        clearRecentConfirmFormat: "Clear unpinned (%d)?",
        clearRecentConfirmMessage: "Pinned items stay, and so does anything copied after this. This can’t be undone.",
        historyLayout: "History layout",
        historyLayoutCards: "Cards",
        historyLayoutList: "List"
    )

    static let fr = ClipboardFeatureStrings(
        title: "Presse-papiers",
        enable: "Enregistrer l’historique du presse-papiers",
        caption: "Enregistre le texte copié pour le réutiliser plus tard. Tout reste local et peut être effacé à tout moment.",
        localNote: "Tout reste sur ce Mac. Les éléments très volumineux sont ignorés.",
        skipSensitive: "Ignorer le texte qui semble sensible",
        skipSensitiveCaption: "Peut ignorer du texte ordinaire ressemblant à des mots de passe ou à des jetons. Le contenu marqué comme confidentiel par l’app source est toujours exclu.",
        limit: "Limite",
        limitUnlimited: "Illimité",
        showInPanel: "Afficher dans le panneau",
        shortcut: "Raccourci de l’historique",
        shortcutCaption: "Ouvre une fenêtre rapide avec recherche, éléments épinglés et raccourcis ⌘1 à ⌘9 pour coller dans l’app précédente.",
        shortcutHint: "Cliquez sur une ligne pour la coller dans l’app précédente. ⌘+clic en sélectionne plusieurs\u{00A0}; ⌘C copie sans coller.",
        clickRowShortcut: "Cliquer la ligne",
        commandClickShortcut: "⌘ Clic",
        pinned: "Épinglés",
        recent: "Récents",
        pin: "Épingler",
        unpin: "Désépingler",
        clearRecent: "Effacer non épinglés",
        clearRecentKeywords: "Effacer les récents",
        empty: "Aucun texte enregistré",
        disabled: "Activez l’historique pour commencer à enregistrer le texte copié.",
        search: "Rechercher le texte copié",
        copy: "Copier",
        copied: "Copié",
        delete: "Supprimer l’élément",
        selectMultiple: "Ajouter à la pile",
        unselectMultiple: "Retirer de la pile",
        selectShortcutAction: "Sélectionner",
        pasteSelectedFormat: "Coller %d",
        copySelectedFormat: "Copier %d",
        clearSelection: "Effacer la sélection",
        moveUp: "Monter",
        moveDown: "Descendre",
        noResults: "Aucun résultat",
        active: "Enregistre le nouveau texte",
        includeImagesFiles: "Enregistrer aussi les images et fichiers copiés",
        includeImagesFilesCaption: "Les images rejoignent l’historique et les fichiers sont mémorisés comme des liens vers leur emplacement. Épinglez-les et collez-les comme du texte.",
        imageEntryLabel: "Image",
        fileCountFormat: "%d fichiers",
        pasteImageAsFile: "Coller les images copiées comme fichiers",
        pasteImageAsFileCaption: "Lorsque Finder est actif, ⌘V enregistre l’image copiée au format PNG dans le dossier actuel.",
        previewLabel: "Aperçu",
        edit: "Modifier",
        cancel: "Annuler",
        save: "Enregistrer",
        autoClearEnable: "Vider le presse-papiers automatiquement après",
        autoClearSecondsSuffix: "secondes",
        autoClearOnSleep: "Vider le presse-papiers à la mise en veille du Mac",
        autoClearOnDisplaySleep: "Vider le presse-papiers à l’extinction de l’écran",
        autoClearOnScreenLock: "Vider le presse-papiers au verrouillage de l’écran",
        autoClearCaption: "Seul le presse-papiers du système est vidé. Les éléments enregistrés restent dans l’historique.",
        deleteSelectedFormat: "Supprimer %d",
        menuBarPreview: "Afficher la dernière copie dans la barre des menus",
        menuBarPreviewCaption: "Affiche un aperçu raccourci de votre dernière copie à côté de l’icône. Cliquez dessus pour ouvrir l’historique.",
        menuBarPreviewLength: "Longueur de l’aperçu",
        menuBarPreviewLengthSuffix: "caractères",
        clearRecentConfirmFormat: "Effacer non épinglés (%d)\u{00A0}?",
        clearRecentConfirmMessage: "Les éléments épinglés restent, comme tout ce qui sera copié ensuite. Action irréversible.",
        historyLayout: "Disposition de l’historique",
        historyLayoutCards: "Cartes",
        historyLayoutList: "Liste"
    )

}

struct WindowLayoutFeatureStrings {
    let title: String
    let caption: String
    let showInPanel: String
    let gestureSection: String
    let gestureEnable: String
    let gestureCaption: String
    let gestureModifiers: String
    let gestureMove: String
    let gestureResize: String
    let gestureResizeHint: String
    let gestureRaiseWindow: String
    let shortcuts: String
    let shortcutsCaption: String
    let permissionCaption: String
    let noWindow: String
    let missingPermission: String
    let failed: String
    let done: String
    let restored: String
    let noRestore: String
    let target: String
    let halves: String
    let thirds: String
    let quarterRows: String
    let quarterColumns: String
    let sixths: String
    let corners: String
    let other: String
    let leftHalf: String
    let rightHalf: String
    let topHalf: String
    let bottomHalf: String
    let centerHalf: String
    let leftThird: String
    let centerThird: String
    let rightThird: String
    let leftTwoThirds: String
    let rightTwoThirds: String
    let centerTwoThirds: String
    let topThird: String
    let middleThird: String
    let bottomThird: String
    let topTwoThirds: String
    let bottomTwoThirds: String
    let topQuarter: String
    let upperMiddleQuarter: String
    let lowerMiddleQuarter: String
    let bottomQuarter: String
    let leftQuarter: String
    let leftMiddleQuarter: String
    let rightMiddleQuarter: String
    let rightQuarter: String
    let topLeftSixth: String
    let topCenterSixth: String
    let topRightSixth: String
    let bottomLeftSixth: String
    let bottomCenterSixth: String
    let bottomRightSixth: String
    let topLeft: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String
    let maximize: String
    let center: String
    let nextDisplay: String
    let restore: String
    let fullScreen: String
    let previousDisplay: String
    let edgeSnapEnable: String
    let edgeSnapCaption: String
    let edgeSnapSystemConflict: String
    let edgeSnapOpenSystemSettings: String
    let edgeSnapWaitingForSystem: String
    let edgeSnapUseCorner: String
    let edgeSnapUseEdge: String
    let edgeSnapAreasOnEdge: String
    let marginMaximize: String
    let marginPerEdge: String
    let gapsSection: String
    let gapsCaption: String
    let windowGap: String
    let screenGap: String
    let sideRepeatCycle: String
    let sideRepeatCycleCaption: String
    let gapNone: String
    let gapTiny: String
    let gapSmall: String
    let gapMedium: String
    let gapLarge: String
    let gapExtraLarge: String

    static let enUS = WindowLayoutFeatureStrings(
        title: "Window layout",
        caption: "Arrange windows into screen sections or move and resize them with a trackpad or mouse.",
        showInPanel: "Show in panel",
        gestureSection: "Window dragging",
        gestureEnable: "Move and resize by dragging",
        gestureCaption: "On a trackpad or mouse, hold the shown modifier keys and drag anywhere inside a window.",
        gestureModifiers: "Keys to move",
        gestureMove: "Drag to move",
        gestureResize: "Add Shift and drag to resize",
        gestureResizeHint: "The starting point chooses the nearest edge or corner. On a mouse, right-button drag also resizes.",
        gestureRaiseWindow: "Bring the dragged window to front",
        shortcuts: "Shortcuts",
        shortcutsCaption: "Use global shortcuts to arrange the active window without opening the panel.",
        permissionCaption: "Uses Accessibility only to move and resize windows.",
        noWindow: "No active window found.",
        missingPermission: "Grant Accessibility to move windows.",
        failed: "Could not move this window.",
        done: "Window arranged.",
        restored: "Window restored.",
        noRestore: "No previous layout to restore.",
        target: "Active window",
        halves: "Halves",
        thirds: "Thirds",
        quarterRows: "Quarter rows",
        quarterColumns: "Quarter columns",
        sixths: "Sixths",
        corners: "Corners",
        other: "Actions",
        leftHalf: "Left",
        rightHalf: "Right",
        topHalf: "Top",
        bottomHalf: "Bottom",
        centerHalf: "Center half",
        leftThird: "Left 1/3",
        centerThird: "Center 1/3",
        rightThird: "Right 1/3",
        leftTwoThirds: "Left 2/3",
        rightTwoThirds: "Right 2/3",
        centerTwoThirds: "Center 2/3",
        topThird: "Top 1/3",
        middleThird: "Middle 1/3",
        bottomThird: "Bottom 1/3",
        topTwoThirds: "Top 2/3",
        bottomTwoThirds: "Bottom 2/3",
        topQuarter: "Top 1/4",
        upperMiddleQuarter: "Upper middle 1/4",
        lowerMiddleQuarter: "Lower middle 1/4",
        bottomQuarter: "Bottom 1/4",
        leftQuarter: "Left 1/4",
        leftMiddleQuarter: "Left middle 1/4",
        rightMiddleQuarter: "Right middle 1/4",
        rightQuarter: "Right 1/4",
        topLeftSixth: "Top left 1/6",
        topCenterSixth: "Top center 1/6",
        topRightSixth: "Top right 1/6",
        bottomLeftSixth: "Bottom left 1/6",
        bottomCenterSixth: "Bottom center 1/6",
        bottomRightSixth: "Bottom right 1/6",
        topLeft: "Top left",
        topRight: "Top right",
        bottomLeft: "Bottom left",
        bottomRight: "Bottom right",
        maximize: "Maximize",
        center: "Center",
        nextDisplay: "Next display",
        restore: "Restore",
        fullScreen: "Full Screen",
        previousDisplay: "Previous display",
        edgeSnapEnable: "Snap windows at screen edges",
        edgeSnapCaption: "Turn this on and drag a window title bar to a highlighted area below. A window moved by holding the modifier keys snaps too. Click an area to choose where the window goes.",
        edgeSnapSystemConflict: "macOS is using the same edges. Turn off window tiling in Desktop & Dock so Mac Island can take over.",
        edgeSnapOpenSystemSettings: "Open Desktop & Dock",
        edgeSnapWaitingForSystem: "Enabled in Mac Island. It starts working as soon as macOS tiling is off.",
        edgeSnapUseCorner: "Use this corner",
        edgeSnapUseEdge: "Use this edge",
        edgeSnapAreasOnEdge: "Areas on this edge",
        marginMaximize: "Maximize with Margin",
        marginPerEdge: "Margin per edge",
        gapsSection: "Gaps",
        gapsCaption: "Space between snapped windows, and between windows and the screen edge.",
        windowGap: "Window gap",
        screenGap: "Screen gap",
        sideRepeatCycle: "Repeat Left or Right to cycle sizes",
        sideRepeatCycleCaption: "Half, then two thirds, then one third on the same display. Off, with more than one display, the repeat moves the window to the next display on that side.",
        gapNone: "None",
        gapTiny: "Tiny",
        gapSmall: "Small",
        gapMedium: "Medium",
        gapLarge: "Large",
        gapExtraLarge: "Extra large"
    )

    static let fr = WindowLayoutFeatureStrings(
        title: "Disposition des fenêtres",
        caption: "Organisez les fenêtres dans des zones de l’écran ou déplacez-les et redimensionnez-les au trackpad ou à la souris.",
        showInPanel: "Afficher dans le panneau",
        gestureSection: "Glissement des fenêtres",
        gestureEnable: "Déplacer et redimensionner par glissement",
        gestureCaption: "Au trackpad ou à la souris, maintenez les touches indiquées et faites glisser depuis n’importe quel point d’une fenêtre.",
        gestureModifiers: "Touches pour déplacer",
        gestureMove: "Faites glisser pour déplacer",
        gestureResize: "Ajoutez Maj et faites glisser pour redimensionner",
        gestureResizeHint: "Le point de départ choisit le bord ou le coin. À la souris, le glissement avec le bouton droit redimensionne aussi.",
        gestureRaiseWindow: "Placer la fenêtre déplacée au premier plan",
        shortcuts: "Raccourcis",
        shortcutsCaption: "Utilisez des raccourcis globaux pour organiser la fenêtre active sans ouvrir le panneau.",
        permissionCaption: "Utilise Accessibilité uniquement pour déplacer et redimensionner les fenêtres.",
        noWindow: "Aucune fenêtre active trouvée.",
        missingPermission: "Autorisez Accessibilité pour déplacer les fenêtres.",
        failed: "Impossible de déplacer cette fenêtre.",
        done: "Fenêtre organisée.",
        restored: "Fenêtre restaurée.",
        noRestore: "Aucune disposition précédente à restaurer.",
        target: "Fenêtre active",
        halves: "Moitiés",
        thirds: "Tiers",
        quarterRows: "Rangées de 1/4",
        quarterColumns: "Colonnes de 1/4",
        sixths: "Sixièmes",
        corners: "Coins",
        other: "Actions",
        leftHalf: "Gauche",
        rightHalf: "Droite",
        topHalf: "Haut",
        bottomHalf: "Bas",
        centerHalf: "Moitié centrée",
        leftThird: "1/3 gauche",
        centerThird: "1/3 centre",
        rightThird: "1/3 droite",
        leftTwoThirds: "2/3 gauche",
        rightTwoThirds: "2/3 droite",
        centerTwoThirds: "2/3 centre",
        topThird: "1/3 haut",
        middleThird: "1/3 milieu",
        bottomThird: "1/3 bas",
        topTwoThirds: "2/3 haut",
        bottomTwoThirds: "2/3 bas",
        topQuarter: "1/4 haut",
        upperMiddleQuarter: "1/4 milieu haut",
        lowerMiddleQuarter: "1/4 milieu bas",
        bottomQuarter: "1/4 bas",
        leftQuarter: "1/4 gauche",
        leftMiddleQuarter: "1/4 milieu gauche",
        rightMiddleQuarter: "1/4 milieu droite",
        rightQuarter: "1/4 droite",
        topLeftSixth: "1/6 en haut à gauche",
        topCenterSixth: "1/6 en haut au centre",
        topRightSixth: "1/6 en haut à droite",
        bottomLeftSixth: "1/6 en bas à gauche",
        bottomCenterSixth: "1/6 en bas au centre",
        bottomRightSixth: "1/6 en bas à droite",
        topLeft: "Haut gauche",
        topRight: "Haut droite",
        bottomLeft: "Bas gauche",
        bottomRight: "Bas droite",
        maximize: "Agrandir",
        center: "Centrer",
        nextDisplay: "Écran suivant",
        restore: "Restaurer",
        fullScreen: "Plein écran",
        previousDisplay: "Écran précédent",
        edgeSnapEnable: "Ancrer les fenêtres aux bords de l’écran",
        edgeSnapCaption: "Activez, puis faites glisser la barre de titre d’une fenêtre vers l’une des zones surlignées ci-dessous. Une fenêtre déplacée avec les touches de modification s’ancre aussi. Cliquez sur une zone pour choisir où va la fenêtre.",
        edgeSnapSystemConflict: "macOS utilise les mêmes bords. Désactivez le placement des fenêtres dans Bureau et Dock pour laisser Mac Island prendre le relais.",
        edgeSnapOpenSystemSettings: "Ouvrir Bureau et Dock",
        edgeSnapWaitingForSystem: "Activé dans Mac Island. Il fonctionnera dès que le placement des fenêtres de macOS sera désactivé.",
        edgeSnapUseCorner: "Utiliser ce coin",
        edgeSnapUseEdge: "Utiliser ce bord",
        edgeSnapAreasOnEdge: "Zones sur ce bord",
        marginMaximize: "Agrandir avec marge",
        marginPerEdge: "Marge de chaque côté",
        gapsSection: "Espacements",
        gapsCaption: "Espace entre les fenêtres ancrées et entre les fenêtres et le bord de l’écran.",
        windowGap: "Espace entre fenêtres",
        screenGap: "Espace au bord de l’écran",
        sideRepeatCycle: "Répéter Gauche ou Droite alterne les tailles",
        sideRepeatCycleCaption: "Moitié, puis deux tiers et un tiers sur le même écran. Désactivé et avec plusieurs écrans, la répétition déplace la fenêtre vers l’écran suivant de ce côté.",
        gapNone: "Aucun",
        gapTiny: "Minuscule",
        gapSmall: "Petit",
        gapMedium: "Moyen",
        gapLarge: "Grand",
        gapExtraLarge: "Très grand"
    )

}

struct MonitorAlertFeatureStrings {
    let section: String
    let caption: String
    let notificationsDenied: String
    let cpu: String
    let cpuTemperature: String
    let memory: String
    let disk: String
    let battery: String
    let cpuThreshold: String
    let cpuTemperatureThreshold: String
    let diskThreshold: String
    let batteryThreshold: String
    let cooldown: String
    let cooldown2: String
    let cooldown5: String
    let cooldown15: String
    let cooldown30: String
    let cooldown60: String
    let cpuTitle: String
    let cpuBodyFormat: String
    let cpuTemperatureTitle: String
    let cpuTemperatureBodyFormat: String
    let memoryTitle: String
    let memoryBody: String
    let diskTitle: String
    let diskBodyFormat: String
    let batteryTitle: String
    let batteryBodyFormat: String
    let batteryTemperature: String
    let batteryTemperatureThreshold: String
    let batteryTemperatureTitle: String
    let batteryTemperatureBodyFormat: String

    static let enUS = MonitorAlertFeatureStrings(
        section: "Alerts",
        caption: "Alerts fire when their selected limits are reached. CPU use and temperature alerts ignore spikes shorter than about 12 seconds. The repeat setting only limits repeats of the same alert.",
        notificationsDenied: "Notifications for Mac Island are off in System Settings, so alerts cannot appear.",
        cpu: "High CPU",
        cpuTemperature: "High CPU temperature",
        memory: "Critical memory pressure",
        disk: "Low disk space",
        battery: "Low battery",
        cpuThreshold: "CPU above",
        cpuTemperatureThreshold: "Temperature above",
        diskThreshold: "Free space below",
        batteryThreshold: "Battery below",
        cooldown: "Repeat the same alert after",
        cooldown2: "2 minutes",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 hour",
        cpuTitle: "High CPU",
        cpuBodyFormat: "CPU stayed above %d%% for a few seconds.",
        cpuTemperatureTitle: "Hot CPU",
        cpuTemperatureBodyFormat: "CPU reached %@.",
        memoryTitle: "Critical memory",
        memoryBody: "Memory pressure reached the critical level.",
        diskTitle: "Low disk space",
        diskBodyFormat: "%@ has less than %d%% free.",
        batteryTitle: "Low battery",
        batteryBodyFormat: "Battery is at %d%%.",
        batteryTemperature: "High battery temperature",
        batteryTemperatureThreshold: "Temperature above",
        batteryTemperatureTitle: "Hot battery",
        batteryTemperatureBodyFormat: "Battery reached %@."
    )

    static let fr = MonitorAlertFeatureStrings(
        section: "Alertes",
        caption: "Les alertes apparaissent lorsque les seuils choisis sont atteints. L’utilisation du processeur et les alertes de température ignorent les pics de moins de 12 secondes environ. Le réglage de répétition limite uniquement la répétition de la même alerte.",
        notificationsDenied: "Les notifications de Mac Island sont désactivées dans Réglages Système, les alertes ne peuvent donc pas apparaître.",
        cpu: "CPU élevé",
        cpuTemperature: "Température CPU élevée",
        memory: "Pression mémoire critique",
        disk: "Espace disque faible",
        battery: "Batterie faible",
        cpuThreshold: "CPU au-dessus de",
        cpuTemperatureThreshold: "Température au-dessus de",
        diskThreshold: "Espace libre sous",
        batteryThreshold: "Batterie sous",
        cooldown: "Répéter la même alerte après",
        cooldown2: "2 minutes",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 heure",
        cpuTitle: "CPU élevé",
        cpuBodyFormat: "Le CPU est resté au-dessus de %d%% pendant quelques secondes.",
        cpuTemperatureTitle: "CPU chaud",
        cpuTemperatureBodyFormat: "Le CPU a atteint %@.",
        memoryTitle: "Mémoire critique",
        memoryBody: "La pression mémoire a atteint le niveau critique.",
        diskTitle: "Espace disque faible",
        diskBodyFormat: "%@ a moins de %d%% libre.",
        batteryTitle: "Batterie faible",
        batteryBodyFormat: "La batterie est à %d%%.",
        batteryTemperature: "Température de la batterie élevée",
        batteryTemperatureThreshold: "Température au-dessus de",
        batteryTemperatureTitle: "Batterie chaude",
        batteryTemperatureBodyFormat: "La batterie a atteint %@."
    )

}

extension SettingsCategoryStrings {
}

extension ClipboardFeatureStrings {
}

extension WindowLayoutFeatureStrings {
}

extension MonitorAlertFeatureStrings {
}

extension MixerFeatureStrings {
}
