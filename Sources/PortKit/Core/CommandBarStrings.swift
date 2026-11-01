// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Localized strings for the command bar, the type-and-run field that finds
/// everything the app can do. Action rows reuse each feature's own strings;
/// only the bar's chrome lives here.
struct CommandBarFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let settingsCaption: String
    let openButton: String
    let searchPlaceholder: String
    let suggestionsLabel: String
    let noResultsTitle: String
    let noResultsAction: String
    let argumentRangeFormat: String
    let argumentHint: String
    let confirmHint: String
    let kindApp: String
    let kindClipboard: String
    let kindSnippet: String
    let soundOutputSubtitle: String
    let soundOutputCurrent: String
    let volumeTitle: String
    let brightnessTitle: String
    let brightnessKeywords: String
    let keepAwakeForFormat: String
    let needsSetupFormat: String
    let needsPermissionHint: String
    let actionCheckAppUpdates: String
    let actionCleanURL: String
    let actionOpenSettings: String
    let answerBatteryLabel: String
    let answerBatteryCharging: String
    let answerBatteryPlugged: String
    let answerMemoryLabel: String
    let answerMemoryFormat: String
    let answerStorageLabel: String
    let answerStorageFormat: String
    let copyHint: String
    let copyFailed: String
    let kindWindow: String
    let quitFormat: String
    let quitConfirmFormat: String
    let kindMenu: String
    let actionsTitle: String
    let actionsHint: String
    let reuseHint: String
    let actionPin: String
    let actionUnpin: String
    let actionName: String
    let actionRename: String
    let actionHide: String
    let actionForget: String
    let aliasPlaceholder: String
    let aliasTakenFormat: String
    let sourcesTitle: String
    let sourcesCaption: String
    let sourceActions: String
    let sourceApps: String
    let sourceMenus: String
    let sourceWindows: String
    let sourceQuitApps: String
    let sourceSettingsPages: String
    let sourceSnippets: String
    let sourceClipboard: String
    let sourceEmoji: String
    let sourceFolders: String
    let sourceAnswers: String
    let sourceCalculator: String
    let namedTitle: String
    let namedEmpty: String
    let pinnedTitle: String
    let pinnedEmpty: String
    let hiddenTitle: String
    let hiddenEmpty: String
    let forgetAllButton: String
    let tryTheseLabel: String
    let stillLooking: String
    let removeButton: String
    let confirmButton: String
    let soundMute: String
    let soundUnmute: String
    let stateOn: String
    let powerSleep: String
    let powerRestart: String
    let powerRestartConfirm: String
    let powerShutDown: String
    let powerShutDownConfirm: String
    let powerLogOut: String
    let powerLogOutConfirm: String
    let wifiOn: String
    let wifiOff: String
    let kindEmoji: String
    let kindFolder: String
    let answerDateLabel: String
    let answerTimeLabel: String
    let kindAnswer: String
    let kindSelection: String
    let selectedTitle: String
    let selectionCopy: String
    let selectionSearch: String
    let selectionUpper: String
    let selectionLower: String
    let selectionTitleCase: String
    let selectionShelf: String
    let selectionCount: String
    let selectionCountFormat: String
    let sourceSelection: String
    let kindLink: String
    let linkSearchHint: String
    let linksTitle: String
    let linksEmpty: String
    let linkDestinationLabel: String
    let linkKindLink: String
    let linkKindPlace: String
    let linkPlaceholdersHint: String
    let placeholderQuery: String
    let placeholderClipboard: String
    let placeholderSelection: String
    let placeholderDate: String
    let privacyNote: String
    let actionShortcut: String
    let actionShortcutChange: String
    let actionShortcutRemove: String
    let shortcutCaptureHint: String
    let rowShortcutsTitle: String
    let rowShortcutsEmpty: String
    let appCenterTitle: String
    let appCenterCaption: String
    let appAliasLabel: String
    let appShortcutLabel: String
    let appShortcutsFilter: String
    let appShortcutRecord: String
    let rowShortcutsLimitFormat: String
    let turnOnFormat: String
    let turnOffFormat: String
    let everythingTitle: String
    let categoryAll: String
    let restartAppFormat: String
    let forceQuitAppFormat: String
    let forceQuitAppConfirmFormat: String
    let uninstallAppFormat: String
    let openInBrowser: String
    let linkKindScript: String
    let scriptHint: String
    let scriptRunsWithoutArgument: String
    let scriptRunsDirectly: String
    let scriptRunFailed: String
    let scriptSearchHint: String
    let scriptBareSearchHint: String
    let linkAddButton: String
    let positionCaption: String
    let resetPositionButton: String
    let shortcutToggle: String
    let dragHint: String
    let actionRevealInFinder: String
    let sourceMacSettings: String
    let sourceFiles: String
    let filesTitle: String
    let filesCaption: String
    let filesEmpty: String
    let filesAddFolder: String
    let filesIgnoreCaption: String
    let filesIgnorePlaceholder: String
    let filesIgnoreAdd: String
    let compactModeToggle: String
    let compactModeCaption: String
    let emojiSkinToneLabel: String
    let emojiSkinToneCaption: String
    let asciiLayoutToggle: String
    let asciiLayoutCaption: String
}

extension FeatureStrings {
    static func commandBar(_ language: AppLanguage) -> CommandBarFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension CommandBarFeatureStrings {
    static let enUS = CommandBarFeatureStrings(
        pageTitle: "Command Bar",
        hubDescription: "One field that finds and runs everything the app does",
        panelCaption: "Type to find and run anything",
        settingsCaption: "One shortcut opens a field over whatever you are doing. Type a few letters, press Return and it happens. Nothing you type is saved.",
        openButton: "Open the bar now",
        searchPlaceholder: "Type what you want to do",
        suggestionsLabel: "Suggestions",
        noResultsTitle: "Nothing here by that name.",
        noResultsAction: "See suggestions",
        argumentRangeFormat: "%d to %d",
        argumentHint: "Return applies · Esc goes back",
        confirmHint: "Return confirms · Esc cancels",
        kindApp: "App",
        kindClipboard: "Paste from history",
        kindSnippet: "Insert snippet",
        soundOutputSubtitle: "Switch sound output",
        soundOutputCurrent: "Current output",
        volumeTitle: "Volume",
        brightnessTitle: "Display brightness",
        brightnessKeywords: "screen",
        keepAwakeForFormat: "Keep awake for %@",
        needsSetupFormat: "Turn on %@ in Settings",
        needsPermissionHint: "Needs permission · Return asks",
        actionCheckAppUpdates: "Check for app updates",
        actionCleanURL: "Clean the copied link",
        actionOpenSettings: "Open Settings",
        answerBatteryLabel: "Battery",
        answerBatteryCharging: "charging",
        answerBatteryPlugged: "on power",
        answerMemoryLabel: "Memory",
        answerMemoryFormat: "%@ of %@ in use",
        answerStorageLabel: "Storage",
        answerStorageFormat: "%@ available of %@",
        copyHint: "Return copies",
        copyFailed: "Couldn’t copy",
        kindWindow: "Window",
        quitFormat: "Quit %@",
        quitConfirmFormat: "Quit %@?",
        kindMenu: "Menu command",
        actionsTitle: "Actions",
        actionsHint: "Actions",
        reuseHint: "Continue",
        actionPin: "Pin to the top",
        actionUnpin: "Unpin",
        actionName: "Give it your own name",
        actionRename: "Change the name it answers to",
        actionHide: "Never show this",
        actionForget: "Forget how often I use this",
        aliasPlaceholder: "The name you call it",
        aliasTakenFormat: "%@ already answers to that",
        sourcesTitle: "What the bar searches",
        sourcesCaption: "Turn off what you never want to see. Your own actions always stay.",
        sourceActions: "Mac Island actions",
        sourceApps: "Apps",
        sourceMenus: "Menu commands of the app in front",
        sourceWindows: "Open windows",
        sourceQuitApps: "Quit an app",
        sourceSettingsPages: "Settings pages",
        sourceSnippets: "Snippets",
        sourceClipboard: "Clipboard history",
        sourceEmoji: "Emoji",
        sourceFolders: "Folders",
        sourceAnswers: "Answers about this Mac",
        sourceCalculator: "Sums and conversions",
        namedTitle: "Names you gave",
        namedEmpty: "Nothing named yet. Open the bar, pick a row and press the actions key.",
        pinnedTitle: "Pinned",
        pinnedEmpty: "Nothing pinned yet.",
        hiddenTitle: "Never shown",
        hiddenEmpty: "Nothing hidden.",
        forgetAllButton: "Forget what I use most",
        tryTheseLabel: "Try",
        stillLooking: "Still looking",
        removeButton: "Remove",
        confirmButton: "Confirm",
        soundMute: "Mute the sound",
        soundUnmute: "Turn the sound back on",
        stateOn: "on",
        powerSleep: "Sleep",
        powerRestart: "Restart",
        powerRestartConfirm: "Restart the Mac?",
        powerShutDown: "Shut down",
        powerShutDownConfirm: "Shut down the Mac?",
        powerLogOut: "Log out",
        powerLogOutConfirm: "Log out?",
        wifiOn: "Turn Wi-Fi on",
        wifiOff: "Turn Wi-Fi off",
        kindEmoji: "Emoji",
        kindFolder: "Folder",
        answerDateLabel: "Today",
        answerTimeLabel: "Time now",
        kindAnswer: "Answer",
        kindSelection: "Selection",
        selectedTitle: "Selected",
        selectionCopy: "Copy it",
        selectionSearch: "Use it in the search",
        selectionUpper: "UPPERCASE",
        selectionLower: "lowercase",
        selectionTitleCase: "Title Case",
        selectionShelf: "Keep it on the shelf",
        selectionCount: "Count it",
        selectionCountFormat: "Words: %d, characters: %d",
        sourceSelection: "What is selected",
        kindLink: "Your shortcut",
        linkSearchHint: "Type what to look for after the name",
        linksTitle: "Your shortcuts",
        linksEmpty: "Nothing saved yet. Add a site, folder, search or script you use every day.",
        linkDestinationLabel: "Where it goes",
        linkKindLink: "Site or link",
        linkKindPlace: "Folder or file",
        linkPlaceholdersHint: "Drop one of these in and it gets filled in when it opens",
        placeholderQuery: "what you type",
        placeholderClipboard: "what you copied",
        placeholderSelection: "what is selected",
        placeholderDate: "today",
        privacyNote: "Search runs on this Mac with no account or cloud, and what you type leaves it only through sites you open or scripts you add.",
        actionShortcut: "Give it a shortcut",
        actionShortcutChange: "Change the shortcut",
        actionShortcutRemove: "Take the shortcut off",
        shortcutCaptureHint: "Press the keys you want · Delete clears it · Esc goes back",
        rowShortcutsTitle: "Rows with their own shortcut",
        rowShortcutsEmpty: "No row has its own shortcut yet. Open the actions on any row to give it one.",
        appCenterTitle: "App shortcuts",
        appCenterCaption: "Open apps with their own shortcuts, even when the bar is closed. Set search names and pin favorites here.",
        appAliasLabel: "Alias",
        appShortcutLabel: "Shortcut",
        appShortcutsFilter: "With shortcuts",
        appShortcutRecord: "Record…",
        rowShortcutsLimitFormat: "You can assign up to %d shortcuts. Remove one to add another.",
        turnOnFormat: "Turn on %@",
        turnOffFormat: "Turn off %@",
        everythingTitle: "Everything it can do",
        categoryAll: "All",
        restartAppFormat: "Restart %@",
        forceQuitAppFormat: "Force Quit %@…",
        forceQuitAppConfirmFormat: "Force quit %@? Unsaved changes will be lost.",
        uninstallAppFormat: "Uninstall %@…",
        openInBrowser: "Open in browser",
        linkKindScript: "Script",
        scriptHint: "Choose an executable file. Type its name followed by what you want to send. It runs when you pause and shows the result here.",
        scriptRunsWithoutArgument: "Also run when its name is typed on its own",
        scriptRunsDirectly: "Run from its global shortcut without opening the bar",
        scriptRunFailed: "Couldn’t run this file",
        scriptSearchHint: "Type what to send after the name",
        scriptBareSearchHint: "Runs on its own, or type what to send",
        linkAddButton: "Add shortcut",
        positionCaption: "Drag the mark at the left of the field to put the bar anywhere on the screen; double-click the mark to recenter it.",
        resetPositionButton: "Recenter the bar",
        shortcutToggle: "Global shortcut to open the bar",
        dragHint: "Drag to move · Double-click to recenter",
        actionRevealInFinder: "Show in Finder",
        sourceMacSettings: "System Settings panes",
        sourceFiles: "Files",
        filesTitle: "Search your files",
        filesCaption: "Name the folders to look in and the bar finds files by name as you type. Nothing is indexed and no permission is asked for: it uses the Mac’s own search and offers only what you can already see in Finder.",
        filesEmpty: "No folders yet, so the bar looks for no files.",
        filesAddFolder: "Add a folder",
        filesIgnoreCaption: "Names never worth showing: a whole folder or file name, or an extension written as *.log.",
        filesIgnorePlaceholder: "A folder or file name",
        filesIgnoreAdd: "Add",
        compactModeToggle: "Compact mode",
        compactModeCaption: "Bar opens without suggestions. Results appear as you type.",
        emojiSkinToneLabel: "Skin tone",
        emojiSkinToneCaption: "By default, emoji that can take a tone use this one. Open the actions on an emoji row to choose a different one.",
        asciiLayoutToggle: "Switch to an ABC layout while the bar is open",
        asciiLayoutCaption: "The field types Latin characters whatever layout was active, and the previous layout comes back when the bar closes.")

    static let fr = CommandBarFeatureStrings(
        pageTitle: "Barre de commande",
        hubDescription: "Un champ qui trouve et lance tout ce que fait l’app",
        panelCaption: "Tapez pour trouver et lancer ce que vous voulez",
        settingsCaption: "Un raccourci ouvre un champ par-dessus ce que vous faites. Tapez quelques lettres, appuyez sur Retour, c’est fait. Rien de ce que vous tapez n’est enregistré.",
        openButton: "Ouvrir la barre maintenant",
        searchPlaceholder: "Tapez ce que vous voulez faire",
        suggestionsLabel: "Suggestions",
        noResultsTitle: "Rien à ce nom par ici.",
        noResultsAction: "Voir les suggestions",
        argumentRangeFormat: "%d à %d",
        argumentHint: "Retour applique · Échap revient",
        confirmHint: "Retour confirme · Échap annule",
        kindApp: "App",
        kindClipboard: "Coller depuis l’historique",
        kindSnippet: "Insérer un extrait",
        soundOutputSubtitle: "Changer la sortie audio",
        soundOutputCurrent: "Sortie actuelle",
        volumeTitle: "Volume",
        brightnessTitle: "Luminosité de l’écran",
        brightnessKeywords: "écran",
        keepAwakeForFormat: "Garder éveillé pendant %@",
        needsSetupFormat: "Activez %@ dans les Réglages",
        needsPermissionHint: "Autorisation nécessaire · Retour la demande",
        actionCheckAppUpdates: "Rechercher les mises à jour des apps",
        actionCleanURL: "Nettoyer le lien copié",
        actionOpenSettings: "Ouvrir les Réglages",
        answerBatteryLabel: "Batterie",
        answerBatteryCharging: "en charge",
        answerBatteryPlugged: "sur secteur",
        answerMemoryLabel: "Mémoire",
        answerMemoryFormat: "%@ sur %@ utilisés",
        answerStorageLabel: "Stockage",
        answerStorageFormat: "%@ disponibles sur %@",
        copyHint: "Retour copie",
        copyFailed: "Impossible de copier",
        kindWindow: "Fenêtre",
        quitFormat: "Quitter %@",
        quitConfirmFormat: "Quitter %@\u{00A0}?",
        kindMenu: "Commande de menu",
        actionsTitle: "Actions",
        actionsHint: "Actions",
        reuseHint: "Continuer",
        actionPin: "Épingler en haut",
        actionUnpin: "Détacher",
        actionName: "Lui donner votre nom",
        actionRename: "Changer le nom auquel il répond",
        actionHide: "Ne jamais montrer ceci",
        actionForget: "Oublier à quel point je l’utilise",
        aliasPlaceholder: "Le nom que vous employez",
        aliasTakenFormat: "%@ répond déjà à ce nom",
        sourcesTitle: "Ce que la barre cherche",
        sourcesCaption: "Désactivez ce que vous ne voulez jamais voir. Vos actions restent toujours.",
        sourceActions: "Actions Mac Island",
        sourceApps: "Apps",
        sourceMenus: "Commandes de menu de l’app au premier plan",
        sourceWindows: "Fenêtres ouvertes",
        sourceQuitApps: "Quitter une app",
        sourceSettingsPages: "Pages des Réglages",
        sourceSnippets: "Extraits",
        sourceClipboard: "Historique du presse-papiers",
        sourceEmoji: "Émoji",
        sourceFolders: "Dossiers",
        sourceAnswers: "Réponses sur ce Mac",
        sourceCalculator: "Calculs et conversions",
        namedTitle: "Noms que vous avez donnés",
        namedEmpty: "Rien de nommé pour l’instant. Ouvrez la barre, choisissez une ligne, appuyez sur la touche d’actions.",
        pinnedTitle: "Épinglés",
        pinnedEmpty: "Rien d’épinglé pour l’instant.",
        hiddenTitle: "Ne jamais montrer",
        hiddenEmpty: "Rien de masqué.",
        forgetAllButton: "Oublier ce que j’utilise le plus",
        tryTheseLabel: "Essayez",
        stillLooking: "Recherche en cours",
        removeButton: "Retirer",
        confirmButton: "Confirmer",
        soundMute: "Couper le son",
        soundUnmute: "Réactiver le son",
        stateOn: "activé",
        powerSleep: "Suspendre l’activité",
        powerRestart: "Redémarrer",
        powerRestartConfirm: "Redémarrer le Mac\u{00A0}?",
        powerShutDown: "Éteindre",
        powerShutDownConfirm: "Éteindre le Mac\u{00A0}?",
        powerLogOut: "Fermer la session",
        powerLogOutConfirm: "Fermer la session\u{00A0}?",
        wifiOn: "Activer le Wi-Fi",
        wifiOff: "Désactiver le Wi-Fi",
        kindEmoji: "Émoji",
        kindFolder: "Dossier",
        answerDateLabel: "Aujourd’hui",
        answerTimeLabel: "Heure actuelle",
        kindAnswer: "Réponse",
        kindSelection: "Sélection",
        selectedTitle: "Sélectionné",
        selectionCopy: "Copier",
        selectionSearch: "Utiliser dans la recherche",
        selectionUpper: "MAJUSCULES",
        selectionLower: "minuscules",
        selectionTitleCase: "Initiales En Majuscules",
        selectionShelf: "Garder sur l’étagère",
        selectionCount: "Compter",
        selectionCountFormat: "Mots\u{00A0}: %d, caractères\u{00A0}: %d",
        sourceSelection: "Ce qui est sélectionné",
        kindLink: "Votre raccourci",
        linkSearchHint: "Tapez quoi chercher après le nom",
        linksTitle: "Vos raccourcis",
        linksEmpty: "Rien d’enregistré. Ajoutez un site, un dossier, une recherche ou un script que vous utilisez chaque jour.",
        linkDestinationLabel: "Où il mène",
        linkKindLink: "Site ou lien",
        linkKindPlace: "Dossier ou fichier",
        linkPlaceholdersHint: "Mettez-en un et il se remplit à l’ouverture",
        placeholderQuery: "ce que vous tapez",
        placeholderClipboard: "ce que vous avez copié",
        placeholderSelection: "ce qui est sélectionné",
        placeholderDate: "aujourd’hui",
        privacyNote: "La recherche s’exécute sur ce Mac, sans compte ni cloud, et ce que vous tapez n’en sort que par les sites que vous ouvrez ou les scripts que vous ajoutez.",
        actionShortcut: "Lui donner un raccourci",
        actionShortcutChange: "Changer le raccourci",
        actionShortcutRemove: "Retirer le raccourci",
        shortcutCaptureHint: "Appuyez sur les touches voulues · Suppr efface · Échap revient",
        rowShortcutsTitle: "Lignes avec leur raccourci",
        rowShortcutsEmpty: "Aucune ligne n’a encore de raccourci. Ouvrez les actions d’une ligne pour lui en donner un.",
        appCenterTitle: "Raccourcis des apps",
        appCenterCaption: "Ouvrez les apps avec leurs propres raccourcis, même lorsque la barre est fermée. Définissez des alias de recherche et épinglez vos favoris ici.",
        appAliasLabel: "Alias",
        appShortcutLabel: "Raccourci",
        appShortcutsFilter: "Avec raccourci",
        appShortcutRecord: "Enregistrer…",
        rowShortcutsLimitFormat: "Vous pouvez attribuer jusqu’à %d raccourcis. Retirez-en un pour en ajouter un autre.",
        turnOnFormat: "Activer %@",
        turnOffFormat: "Désactiver %@",
        everythingTitle: "Tout ce qu’elle sait faire",
        categoryAll: "Tout",
        restartAppFormat: "Relancer %@",
        forceQuitAppFormat: "Forcer %@ à quitter…",
        forceQuitAppConfirmFormat: "Forcer %@ à quitter\u{00A0}? Les modifications non enregistrées seront perdues.",
        uninstallAppFormat: "Désinstaller %@…",
        openInBrowser: "Ouvrir dans le navigateur",
        linkKindScript: "Script",
        scriptHint: "Choisissez un fichier exécutable. Saisissez son nom suivi du texte à envoyer. Après une pause, le résultat s’affiche ici.",
        scriptRunsWithoutArgument: "Exécuter aussi lorsque le nom est saisi seul",
        scriptRunsDirectly: "Lancer par son raccourci global sans ouvrir la barre",
        scriptRunFailed: "Impossible d’exécuter ce fichier",
        scriptSearchHint: "Saisissez ce qui sera envoyé après le nom",
        scriptBareSearchHint: "S’exécute seul, ou saisissez ce qui sera envoyé",
        linkAddButton: "Ajouter un raccourci",
        positionCaption: "Faites glisser la marque à gauche du champ pour placer la barre où vous voulez à l’écran\u{00A0}; double-cliquez sur la marque pour la recentrer.",
        resetPositionButton: "Recentrer la barre",
        shortcutToggle: "Raccourci global pour ouvrir la barre",
        dragHint: "Glisser pour déplacer · Double-clic pour recentrer",
        actionRevealInFinder: "Afficher dans le Finder",
        sourceMacSettings: "Volets des Réglages Système",
        sourceFiles: "Fichiers",
        filesTitle: "Rechercher vos fichiers",
        filesCaption: "Choisissez les dossiers à explorer et la barre trouve les fichiers par leur nom à mesure que vous tapez. Rien n’est indexé et aucune autorisation n’est demandée\u{00A0}: elle utilise la recherche du Mac et ne propose que ce que vous voyez déjà dans le Finder.",
        filesEmpty: "Aucun dossier pour l’instant, la barre ne cherche donc aucun fichier.",
        filesAddFolder: "Ajouter un dossier",
        filesIgnoreCaption: "Noms à ne jamais montrer\u{00A0}: un dossier ou un fichier entier, ou une extension écrite ainsi\u{00A0}: *.log.",
        filesIgnorePlaceholder: "Nom de dossier ou de fichier",
        filesIgnoreAdd: "Ajouter",
        compactModeToggle: "Mode compact",
        compactModeCaption: "La barre s’ouvre sans suggestions. Les résultats apparaissent à mesure que vous tapez.",
        emojiSkinToneLabel: "Teinte de peau",
        emojiSkinToneCaption: "Par défaut, les émojis qui acceptent une teinte utilisent celle-ci. Ouvrez les actions sur une ligne d’émoji pour en choisir une autre.",
        asciiLayoutToggle: "Passer en disposition ABC quand la barre est ouverte",
        asciiLayoutCaption: "Le champ saisit des caractères latins quelle que soit la disposition active, et la précédente revient à la fermeture de la barre.")

}
