// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct WindowLayoutIgnoredAppsStrings {
    let sectionTitle: String
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowLayoutIgnoredApps(_ language: AppLanguage) -> WindowLayoutIgnoredAppsStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension WindowLayoutIgnoredAppsStrings {
    static let enUS = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ignore apps", listTitle: "Pause in these apps", addButton: "Add an app…", removeButton: "Remove", caption: "Window Layout does not use mouse or keyboard input while one of these apps is focused.")
    static let fr = WindowLayoutIgnoredAppsStrings(sectionTitle: "Apps à ignorer", listTitle: "Mettre en pause dans ces apps", addButton: "Ajouter une app…", removeButton: "Retirer", caption: "Disposition des fenêtres n’utilise ni la souris ni le clavier tant que l’une de ces apps est active.")
}
