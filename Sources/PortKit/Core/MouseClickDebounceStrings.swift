// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct MouseClickDebounceStrings {
    let title: String
    let caption: String
    let moreOptions: String
    let windowLabel: String
    let windowCaption: String
}

extension FeatureStrings {
    static func mouseClickDebounce(_ language: AppLanguage) -> MouseClickDebounceStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension MouseClickDebounceStrings {
    static let enUS = MouseClickDebounceStrings(
        title: "Extra click filter",
        caption: "Ignores rapid extra clicks from worn mouse buttons without slowing normal clicks.",
        moreOptions: "More options",
        windowLabel: "Filter window",
        windowCaption: "A repeated click inside this interval is treated as an accidental duplicate."
    )

    static let fr = MouseClickDebounceStrings(
        title: "Filtre de clics",
        caption: "Ignore les clics supplémentaires rapides des boutons usés sans retarder les clics normaux.",
        moreOptions: "Plus d’options",
        windowLabel: "Intervalle du filtre",
        windowCaption: "Un clic répété dans cet intervalle est considéré comme une répétition accidentelle."
    )

}
