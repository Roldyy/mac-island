// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchLockScreenStrings {
    /// The name System Settings gives its own Lock Screen pane.
    let title: String
    let show: String
    let showHint: String
    let sounds: String
    let soundsHint: String
    /// Beside the names of the agents working while the Mac is locked.
    let working: String
}

extension FeatureStrings {
    static func notchLockScreen(_ language: AppLanguage) -> NotchLockScreenStrings {
        switch language {
        case .enUS: return NotchLockScreenStrings(
            title: "Lock Screen",
            show: "Show on the Lock Screen",
            showHint: "Music and the Dynamic Island’s activities, like a timer, AI agents, downloads and your next event, appear above the password field. Anyone who can see your screen can read them.",
            sounds: "Lock and unlock sounds",
            soundsHint: "Play the macOS padlock sound when your Mac locks and unlocks.",
            working: "Working")
        default: return NotchLockScreenStrings(
            title: "Écran verrouillé",
            show: "Afficher sur l’écran verrouillé",
            showHint: "La musique et les activités du Dynamic Island, comme le minuteur, les agents IA, les téléchargements et votre prochain rendez-vous, apparaissent au-dessus du champ du mot de passe. Toute personne qui voit votre écran peut les lire.",
            sounds: "Sons de verrouillage et de déverrouillage",
            soundsHint: "Joue le son de cadenas de macOS quand votre Mac se verrouille et se déverrouille.",
            working: "En cours")
        }
    }
}
