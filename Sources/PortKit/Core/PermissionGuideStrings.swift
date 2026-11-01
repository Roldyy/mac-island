// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Strings for the floating permission guide: the little card that walks the
/// person through System Settings and notices the grant by itself. Same
/// contract as the other FeatureStrings structs: memberwise init in
/// declaration order, one static per language, all in this file.
struct PermissionGuideStrings {
    let title: String
    let stepOpen: String
    let stepToggle: String
    let stepReturn: String
    let waiting: String
    let granted: String
    let closeHelp: String
    /// Shown once the wait has gone on a while: the usual cause is an entry
    /// left by an earlier copy of the app, which macOS shows as on but no
    /// longer honours.
    let staleHint: String
    let startOver: String
    let relaunch: String
}

extension FeatureStrings {
    static func permissionGuide(_ language: AppLanguage) -> PermissionGuideStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension PermissionGuideStrings {
}

extension PermissionGuideStrings {
    static let enUS = PermissionGuideStrings(
        title: "One step left",
        stepOpen: "macOS opened System Settings on the right list.",
        stepToggle: "Turn Mac Island on in that list.",
        stepReturn: "Come back. This card notices by itself.",
        waiting: "Waiting for the permission…",
        granted: "Permission granted!",
        closeHelp: "Close",
        staleHint: "Already on in that list? That entry belongs to an earlier copy of the app. Start over to replace it.",
        startOver: "Start over",
        relaunch: "Relaunch to apply"
    )

    static let fr = PermissionGuideStrings(
        title: "Plus qu’une étape",
        stepOpen: "macOS a ouvert les Réglages Système sur la bonne liste.",
        stepToggle: "Activez Mac Island dans cette liste.",
        stepReturn: "Revenez ici. Cette carte le remarque toute seule.",
        waiting: "En attente de l’autorisation…",
        granted: "Autorisation accordée\u{00A0}!",
        closeHelp: "Fermer",
        staleHint: "Déjà activé dans cette liste\u{00A0}? Cette entrée appartient à une copie précédente de l’app. Recommencez pour la remplacer.",
        startOver: "Recommencer",
        relaunch: "Relancer pour appliquer"
    )

}
