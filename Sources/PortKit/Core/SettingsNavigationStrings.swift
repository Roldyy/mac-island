// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

struct SettingsNavigationStrings {
    let go: String
    let back: String
    let forward: String
    /// The names macOS gives its own sidebar command in each language.
    let showSidebar: String
    let hideSidebar: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return Self(go: "Go", back: "Back", forward: "Forward",
                        showSidebar: "Show Sidebar", hideSidebar: "Hide Sidebar")
        default:
            return Self(go: "Aller", back: "Précédent", forward: "Suivant",
                        showSidebar: "Afficher la barre latérale", hideSidebar: "Masquer la barre latérale")
        }
    }
}
