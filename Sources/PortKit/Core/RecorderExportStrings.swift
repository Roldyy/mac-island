// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct RecorderExportStrings {
    let speed: String
    let custom: String
    let duration: String
    let previewNote: String
}

extension FeatureStrings {
    static func recorderExport(_ language: AppLanguage) -> RecorderExportStrings {
        switch language {
        case .enUS:
            return RecorderExportStrings(
                speed: "Export speed", custom: "Custom speed", duration: "Export duration",
                previewNote: "Applies to video, GIF and shared links. The editing preview stays at 1×; the original recording is unchanged.")
        default:
            return RecorderExportStrings(
                speed: "Vitesse d’exportation", custom: "Vitesse personnalisée", duration: "Durée exportée",
                previewNote: "S’applique aux vidéos, GIF et liens partagés. L’aperçu de montage reste à 1× ; l’enregistrement original reste inchangé.")
        }
    }
}
