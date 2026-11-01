// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

struct WindowDirectionalStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> WindowDirectionalStrings {
        switch language {
        case .enUS: return .init(title: "Shortcut + pointer layout", caption: "Hold the shortcut, move the pointer toward an edge or corner, then release to place the active window.")
        default: return .init(title: "Raccourci + pointeur", caption: "Maintenez le raccourci, déplacez le pointeur vers un bord ou un coin, puis relâchez pour placer la fenêtre active.")
        }
    }
}
