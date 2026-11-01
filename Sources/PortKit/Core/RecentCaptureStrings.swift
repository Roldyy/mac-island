// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct RecentCaptureStrings {
    let title: String
    let empty: String
    let screenshot: String
    let recording: String
    let restore: String
    let open: String
    let remove: String
    let clear: String
}

extension FeatureStrings {
    static func recentCaptures(_ language: AppLanguage) -> RecentCaptureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension RecentCaptureStrings {
    static let enUS = RecentCaptureStrings(
        title: "Recent captures",
        empty: "Take a screenshot or save a recording to find it here.",
        screenshot: "Screenshot",
        recording: "Recording",
        restore: "Restore",
        open: "Open",
        remove: "Remove from history",
        clear: "Clear history"
    )

    static let fr = RecentCaptureStrings(
        title: "Captures récentes",
        empty: "Prenez une capture ou enregistrez une vidéo pour la retrouver ici.",
        screenshot: "Capture d’écran",
        recording: "Enregistrement",
        restore: "Restaurer",
        open: "Ouvrir",
        remove: "Retirer de l’historique",
        clear: "Effacer l’historique"
    )

}
