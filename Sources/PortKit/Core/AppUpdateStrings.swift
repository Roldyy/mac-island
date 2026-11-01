// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct AppUpdateStrings {
    let pageTitle: String
    let hubDescription: String
    let caption: String
    let panelCaption: String
    let checkNow: String
    let checking: String
    let lastCheckFormat: String
    let neverChecked: String
    let upToDate: String
    let partialUpToDate: String
    let coverageNote: String
    let selectAll: String
    let clearSelection: String
    let updateSelectedFormat: String
    let updateOne: String
    let openAppStore: String
    let appStoreBadge: String
    let storeHint: String
    let frequencyLabel: String
    let frequencyOff: String
    let frequencyDaily: String
    let frequencyWeekly: String
    let nextCheckFormat: String
    let notifyToggle: String
    let includeStoreToggle: String
    let includeStoreCaption: String
    let packageMissing: String
    let notificationBodyFormat: String
    /// Used when exactly one app is waiting, so the note never reads "1 apps".
    let notificationBodyOne: String
    let showInPanel: String
    let homebrewBadge: String
    let sourcesTitle: String
    let includeHomebrewToggle: String
    let onlineBadge: String
    let openApp: String
    let openAppHint: String
    let includeOnlineToggle: String
    let includeOnlineCaption: String
    let incompleteCheck: String
    let onlineUnavailable: String
    let skipVersionFormat: String
    let excludeApp: String
    let rulesTitle: String
    let addException: String
    let skippedVersionFormat: String
    let excludedApp: String
    let removeRule: String
    let rulesHint: String
    let noVisibleUpdates: String
    let uncomparableVersions: String
    let uncomparableVersionsNote: String
}

extension FeatureStrings {
    static func appUpdates(_ language: AppLanguage) -> AppUpdateStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension AppUpdateStrings {
    static let enUS = AppUpdateStrings(
        pageTitle: "App updates",
        hubDescription: "Find and install updates for the apps you have",
        caption: "Looks for newer versions of the apps on this Mac and helps you finish each update from its original source.",
        panelCaption: "See which apps have a newer version",
        checkNow: "Check now",
        checking: "Checking",
        lastCheckFormat: "Last checked %@",
        neverChecked: "Not checked yet",
        upToDate: "No updates found",
        partialUpToDate: "No updates found in this partial check",
        coverageNote: "Checks the original sources of installed apps and a public catalog. Updates install through their original source.",
        selectAll: "Select all",
        clearSelection: "Clear",
        updateSelectedFormat: "Update %d",
        updateOne: "Update",
        openAppStore: "Open the App Store",
        appStoreBadge: "App Store",
        storeHint: "Opens the App Store, where this update is installed",
        frequencyLabel: "Check in the background",
        frequencyOff: "Off",
        frequencyDaily: "Every day",
        frequencyWeekly: "Every week",
        nextCheckFormat: "Next check %@",
        notifyToggle: "Tell me when an app has an update",
        includeStoreToggle: "Include apps from the App Store",
        includeStoreCaption: "Checks store versions using this Mac’s region. Apple installs these updates.",
        packageMissing: "Homebrew is not installed, so apps cannot be updated from here yet.",
        notificationBodyFormat: "%@ apps have a newer version.",
        notificationBodyOne: "One app has a newer version.",
        showInPanel: "Show in panel",
        homebrewBadge: "Homebrew",
        sourcesTitle: "Sources",
        includeHomebrewToggle: "Include Homebrew apps",
        onlineBadge: "Online",
        openApp: "Open",
        openAppHint: "Opens the app so its own updater can finish",
        includeOnlineToggle: "Include other installed apps",
        includeOnlineCaption: "Checks directly with app developers when supported, then uses a public catalog. The app’s own updater installs the update.",
        incompleteCheck: "Check incomplete",
        onlineUnavailable: "The online check could not be completed. Other results are still shown.",
        skipVersionFormat: "Skip version %@",
        excludeApp: "Don’t check this app",
        rulesTitle: "Update exceptions",
        addException: "Add an app that should not be checked",
        skippedVersionFormat: "Skipped version %@",
        excludedApp: "Not checked until this rule is removed",
        removeRule: "Remove",
        rulesHint: "Skipping a version still allows newer releases. After removing an app exclusion, use Check now to refresh it.",
        noVisibleUpdates: "No updates outside your rules",
        uncomparableVersions: "Versions not compared",
        uncomparableVersionsNote: "No update is shown when an app’s own version can’t be compared with the catalog. Check for updates in the app itself."
    )

    static let fr = AppUpdateStrings(
        pageTitle: "Mises à jour des apps",
        hubDescription: "Trouvez et installez les mises à jour de vos apps",
        caption: "Cherche des versions plus récentes des apps de ce Mac et vous aide à terminer chaque mise à jour depuis sa source d’origine.",
        panelCaption: "Voyez quelles apps ont une version plus récente",
        checkNow: "Vérifier maintenant",
        checking: "Vérification",
        lastCheckFormat: "Dernière vérification %@",
        neverChecked: "Pas encore vérifié",
        upToDate: "Aucune mise à jour trouvée",
        partialUpToDate: "Aucune mise à jour trouvée lors de cette vérification partielle",
        coverageNote: "Vérifie les sources d’origine des apps installées et un catalogue public. Les mises à jour s’installent depuis leur source d’origine.",
        selectAll: "Tout sélectionner",
        clearSelection: "Effacer",
        updateSelectedFormat: "Mettre à jour %d",
        updateOne: "Mettre à jour",
        openAppStore: "Ouvrir l’App Store",
        appStoreBadge: "App Store",
        storeHint: "Ouvre l’App Store, où cette mise à jour s’installe",
        frequencyLabel: "Vérifier en arrière-plan",
        frequencyOff: "Désactivé",
        frequencyDaily: "Chaque jour",
        frequencyWeekly: "Chaque semaine",
        nextCheckFormat: "Prochaine vérification %@",
        notifyToggle: "Me prévenir quand une app a une mise à jour",
        includeStoreToggle: "Inclure les apps de l’App Store",
        includeStoreCaption: "Vérifie les versions du magasin pour la région de ce Mac. Apple installe ces mises à jour.",
        packageMissing: "Homebrew n’est pas installé, les apps ne peuvent donc pas encore être mises à jour d’ici.",
        notificationBodyFormat: "%@ apps ont une version plus récente.",
        notificationBodyOne: "Une app a une version plus récente.",
        showInPanel: "Afficher dans le panneau",
        homebrewBadge: "Homebrew",
        sourcesTitle: "Sources",
        includeHomebrewToggle: "Inclure les apps Homebrew",
        onlineBadge: "En ligne",
        openApp: "Ouvrir",
        openAppHint: "Ouvre l’app pour permettre à son propre outil de mise à jour de terminer",
        includeOnlineToggle: "Inclure les autres apps installées",
        includeOnlineCaption: "Consulte directement les développeurs lorsque c’est possible, puis complète la recherche avec un catalogue public. L’app installe elle-même la mise à jour.",
        incompleteCheck: "Vérification incomplète",
        onlineUnavailable: "La vérification en ligne n’a pas pu aboutir. Les autres résultats restent affichés.",
        skipVersionFormat: "Ignorer la version %@",
        excludeApp: "Ne pas vérifier cette app",
        rulesTitle: "Exceptions de mise à jour",
        addException: "Ajouter une app à ne pas vérifier",
        skippedVersionFormat: "Version %@ ignorée",
        excludedApp: "Non vérifiée jusqu’au retrait de cette règle",
        removeRule: "Retirer",
        rulesHint: "Ignorer une version ne masque pas les suivantes. Après avoir retiré une exclusion, utilisez Vérifier maintenant pour actualiser la liste.",
        noVisibleUpdates: "Aucune mise à jour en dehors de vos règles",
        uncomparableVersions: "Versions non comparées",
        uncomparableVersionsNote: "Aucune mise à jour n’est affichée lorsque la version indiquée par une app ne peut pas être comparée au catalogue. Recherchez les mises à jour dans l’app elle-même."
    )

}
