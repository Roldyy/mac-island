// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Strings for the Kill Process feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct KillProcessFeatureStrings {
    let pageTitle: String
    let browseSubtitle: String
    let hubDescription: String
    let searchPlaceholder: String
    let columnProcess: String
    let columnCPU: String
    let columnMemory: String
    let columnPID: String
    let groupToggle: String
    let groupCaption: String
    let commandBarToggle: String
    let commandBarCaption: String
    let refreshTooltip: String
    let pidLabelFormat: String
    let processCountFormat: String
    let killButton: String
    let forceKillButton: String
    let killAllFormat: String
    let killTreeButton: String
    let restartButton: String
    let copyPID: String
    let copyPath: String
    let emptyStateTitle: String
    let confirmKillFormat: String
    let confirmForceKillFormat: String
    let confirmKillAllFormat: String
    let confirmKillTreeFormat: String
    let killFailedTitle: String
    let killFailedMessage: String
    let adminPromptFormat: String
}

extension FeatureStrings {
    static func killProcess(_ language: AppLanguage) -> KillProcessFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension KillProcessFeatureStrings {
    static let enUS = KillProcessFeatureStrings(
        pageTitle: "Kill Process",
        browseSubtitle: "Browse & Kill",
        hubDescription: "Search running processes and force quit, restart, or kill process trees",
        searchPlaceholder: "Filter by name",
        columnProcess: "Process",
        columnCPU: "CPU",
        columnMemory: "Memory",
        columnPID: "PID",
        groupToggle: "Group related processes",
        groupCaption: "Groups helper processes under the app responsible for them.",
        commandBarToggle: "Show in Command Bar",
        commandBarCaption: "Adds running processes to the Command Bar, so you can find and kill them without opening Settings.",
        refreshTooltip: "Refresh",
        pidLabelFormat: "PID %d",
        processCountFormat: "Processes: %d",
        killButton: "Kill",
        forceKillButton: "Force Kill",
        killAllFormat: "Kill All “%@”",
        killTreeButton: "Kill Process Tree",
        restartButton: "Restart",
        copyPID: "Copy PID",
        copyPath: "Copy Path",
        emptyStateTitle: "No Processes Found",
        confirmKillFormat: "Kill %@?",
        confirmForceKillFormat: "Force Kill %@?",
        confirmKillAllFormat: "Kill all “%@” processes?",
        confirmKillTreeFormat: "Kill %@ and all its child processes?",
        killFailedTitle: "Couldn’t Kill Process",
        killFailedMessage: "The process may have already exited or require additional privileges.",
        adminPromptFormat: "Mac Island needs administrator access to end “%@”."
    )

    static let fr = KillProcessFeatureStrings(
        pageTitle: "Forcer à quitter",
        browseSubtitle: "Parcourir et arrêter",
        hubDescription: "Recherchez les processus en cours et forcez-les à quitter, redémarrez-les ou arrêtez leurs arborescences",
        searchPlaceholder: "Filtrer par nom",
        columnProcess: "Processus",
        columnCPU: "CPU",
        columnMemory: "Mémoire",
        columnPID: "PID",
        groupToggle: "Regrouper les processus liés",
        groupCaption: "Regroupe les processus auxiliaires sous l’app qui en est responsable.",
        commandBarToggle: "Afficher dans la Barre de Commandes",
        commandBarCaption: "Ajoute les processus en cours à la Barre de Commandes, pour les trouver et les arrêter sans ouvrir les Réglages.",
        refreshTooltip: "Actualiser",
        pidLabelFormat: "PID %d",
        processCountFormat: "Processus\u{00A0}: %d",
        killButton: "Arrêter",
        forceKillButton: "Forcer l’arrêt",
        killAllFormat: "Arrêter tous les «\u{00A0}%@\u{00A0}»",
        killTreeButton: "Arrêter l’arborescence du processus",
        restartButton: "Redémarrer",
        copyPID: "Copier le PID",
        copyPath: "Copier le chemin",
        emptyStateTitle: "Aucun processus trouvé",
        confirmKillFormat: "Arrêter %@\u{00A0}?",
        confirmForceKillFormat: "Forcer l’arrêt de %@\u{00A0}?",
        confirmKillAllFormat: "Arrêter tous les processus «\u{00A0}%@\u{00A0}»\u{00A0}?",
        confirmKillTreeFormat: "Arrêter %@ et tous ses processus enfants\u{00A0}?",
        killFailedTitle: "Impossible d’arrêter le processus",
        killFailedMessage: "Le processus a peut-être déjà quitté ou nécessite des privilèges supplémentaires.",
        adminPromptFormat: "Mac Island a besoin d’un accès administrateur pour arrêter «\u{00A0}%@\u{00A0}»."
    )

}
