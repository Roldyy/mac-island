// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchGestureStrings {
    let title: String
    let description: String
    let hint: String
}

extension FeatureStrings {
    static func notchGestures(_ language: AppLanguage) -> NotchGestureStrings {
        switch language {
        case .enUS: return NotchGestureStrings(
            title: "Dynamic Island Gestures",
            description: "Open and close the Dynamic Island with scrolling, and swipe to change tracks.",
            hint: "Scroll down to open. Scroll up over the top row to close. Swipe left or right over the music to change tracks. Lists keep their own scrolling.")
        default: return NotchGestureStrings(
            title: "Gestes du Dynamic Island",
            description: "Ouvrez et fermez le Dynamic Island par défilement et balayez pour changer de morceau.",
            hint: "Faites défiler vers le bas pour ouvrir, vers le haut sur la rangée supérieure pour fermer. Balayez latéralement sur la musique pour changer de morceau. Les listes gardent leur défilement.")
        }
    }
}
