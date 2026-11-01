// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

struct NotchLowBatteryStrings {
    let title: String
    let caption: String
    let threshold: String
    let early: String
    let earlyCaption: String
    let earlyThreshold: String
    let menuBar: String

    static func localized(_ language: AppLanguage) -> NotchLowBatteryStrings {
        switch language {
        case .enUS:
            return .init(title: "Turn red when low", caption: "Shows the charge in red at or below this level while on battery.",
                         threshold: "Red level", early: "Turn amber first",
                         earlyCaption: "Shows the charge in amber at or below a higher level, as an early warning.",
                         earlyThreshold: "Amber level", menuBar: "Also in the menu bar")
        default:
            return .init(title: "Passer en rouge si faible", caption: "Affiche la charge en rouge à ce niveau ou en dessous lorsque le Mac est sur batterie.",
                         threshold: "Niveau rouge", early: "Passer d’abord en ambre",
                         earlyCaption: "Affiche la charge en ambre à un niveau plus élevé ou en dessous, comme premier avertissement.",
                         earlyThreshold: "Niveau ambre", menuBar: "Aussi dans la barre des menus")
        }
    }
}
