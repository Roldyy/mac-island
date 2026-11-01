// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchWatchStrings {
    let title: String
    let description: String
    let setupHint: String
    let choose: String
    let chooseAgain: String
    let purpose: String
    let stop: String
    let watchAgain: String
    let permissionHint: String
    let allowAccess: String
    let tellMe: String
    let changes: String
    let settles: String
    let contains: String
    let reaches: String
    let settlesHint: String
    let textPlaceholder: String
    let numberPlaceholder: String
    let noText: String
    let inIsland: String
    let automatic: String
    let hidden: String
    let changedNotice: String
    let settledNotice: String
    let showsFormat: String
    let reachedFormat: String
    let closedNotice: String
    let sinceFormat: String
    let sound: String

    func condition(_ condition: NotchWatchCondition) -> String {
        switch condition {
        case .changes: return changes
        case .settles: return settles
        case .contains: return contains
        case .reaches: return reaches
        }
    }

    func outcome(_ outcome: NotchWatchOutcome) -> String {
        switch outcome {
        case .changed: return changedNotice
        case .settled: return settledNotice
        case .shows(let text): return String(format: showsFormat, text)
        case .reached(let text): return String(format: reachedFormat, text)
        case .closed: return closedNotice
        }
    }

    func since(_ time: String) -> String { String(format: sinceFormat, time) }
}

extension FeatureStrings {
    static func notchWatch(_ language: AppLanguage) -> NotchWatchStrings {
        switch language {
        case .enUS: return NotchWatchStrings(
            title: "Watch",
            description: "Turn any part of any window into a live activity in the Dynamic Island, with an alert when it changes, finishes or shows what you are waiting for.",
            setupHint: "Choose any part of a window, like a progress bar, a build status or a score. The island reads it for you and tells you when it changes.",
            choose: "Choose Area",
            chooseAgain: "Choose Another Area",
            purpose: "Choose what to watch",
            stop: "Stop Watching",
            watchAgain: "Watch Again",
            permissionHint: "Watch reads the area you choose on your Mac, so it needs Screen Recording. Nothing leaves your Mac.",
            allowAccess: "Allow Screen Recording",
            tellMe: "Tell me",
            changes: "When it changes",
            settles: "When it stops changing",
            contains: "When it shows",
            reaches: "When the number reaches",
            settlesHint: "After it changes, it must stay still for 30 seconds.",
            textPlaceholder: "Text, like Done",
            numberPlaceholder: "Number, like 100",
            noText: "No text",
            inIsland: "Show in the island",
            automatic: "Automatic",
            hidden: "The window is hidden. Watching continues when it returns.",
            changedNotice: "It changed",
            settledNotice: "It stopped changing",
            showsFormat: "It shows %@",
            reachedFormat: "It reached %@",
            closedNotice: "The window closed",
            sinceFormat: "Watching since %@",
            sound: "Play a sound")
        default: return NotchWatchStrings(
            title: "Surveiller",
            description: "Transformez n’importe quelle partie d’une fenêtre en activité en direct dans le Dynamic Island, avec une alerte quand elle change, se termine ou affiche ce que vous attendez.",
            setupHint: "Choisissez une partie d’une fenêtre, comme une barre de progression, l’état d’une compilation ou un score. L’île la lit pour vous et vous prévient quand elle change.",
            choose: "Choisir une zone",
            chooseAgain: "Choisir une autre zone",
            purpose: "Choisissez quoi surveiller",
            stop: "Arrêter la surveillance",
            watchAgain: "Surveiller à nouveau",
            permissionHint: "Surveiller lit la zone choisie sur votre Mac, il lui faut donc l’Enregistrement de l’écran. Rien ne quitte votre Mac.",
            allowAccess: "Autoriser l’Enregistrement de l’écran",
            tellMe: "Prévenir",
            changes: "Quand elle change",
            settles: "Quand elle ne change plus",
            contains: "Quand elle affiche",
            reaches: "Quand le nombre atteint",
            settlesHint: "Après un changement, elle doit rester immobile 30 secondes.",
            textPlaceholder: "Texte, comme Terminé",
            numberPlaceholder: "Nombre, comme 100",
            noText: "Aucun texte",
            inIsland: "Afficher dans l’île",
            automatic: "Automatique",
            hidden: "La fenêtre est masquée. La surveillance reprend à son retour.",
            changedNotice: "Elle a changé",
            settledNotice: "Elle ne change plus",
            showsFormat: "Elle affiche %@",
            reachedFormat: "Elle a atteint %@",
            closedNotice: "La fenêtre s’est fermée",
            sinceFormat: "Surveillée depuis %@",
            sound: "Jouer un son")
        }
    }
}
