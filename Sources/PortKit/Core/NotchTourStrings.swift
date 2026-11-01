// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchTourStrings {
    let preview: String
    let caption: String
}

extension FeatureStrings {
    static func notchTour(_ language: AppLanguage) -> NotchTourStrings {
        switch language {
        case .enUS: return NotchTourStrings(preview: "Preview for 3.4",
            caption: "Control music, timers, volume and brightness. Choose the floating shortcuts you use most.")
        default: return NotchTourStrings(preview: "Aperçu de la version 3.4",
            caption: "Contrôlez la musique, les minuteurs, le volume et la luminosité. Choisissez les raccourcis flottants que vous utilisez le plus.")
        }
    }
}
