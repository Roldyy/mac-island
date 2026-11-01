// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

struct GraphScaleStrings {
    let title: String

    static func localized(_ language: AppLanguage) -> GraphScaleStrings {
        switch language {
        case .enUS: return .init(title: "Show graph scale")
        default: return .init(title: "Afficher l’échelle des graphiques")
        }
    }
}
