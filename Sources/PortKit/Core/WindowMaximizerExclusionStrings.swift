// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct WindowMaximizerExclusionStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowMaximizerExclusions(_ language: AppLanguage) -> WindowMaximizerExclusionStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension WindowMaximizerExclusionStrings {
    static let enUS = WindowMaximizerExclusionStrings(
        listTitle: "Keep full screen in these apps",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "The green button keeps its macOS behavior in these apps, so games, emulators and video players can still enter full screen."
    )

    static let fr = WindowMaximizerExclusionStrings(
        listTitle: "Garder le plein écran dans ces apps",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        caption: "Dans ces apps, le bouton vert garde son comportement macOS, pour que les jeux, émulateurs et lecteurs vidéo puissent toujours passer en plein écran."
    )

}
