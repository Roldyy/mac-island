// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

/// User-facing copy when an incoming file fails to finish saving
/// or cannot fit on the shelf after it was accepted.
struct ShelfPromiseDeliveryStrings {
    let failedTitle: String
    let failedBody: String
    let fullTitle: String
    let fullBody: String
    let okButton: String

    static func localized(_ language: AppLanguage) -> ShelfPromiseDeliveryStrings {
        switch language {
        case .enUS:
            return .init(
                failedTitle: "Couldn’t add attachment",
                failedBody: "The file never finished saving to the shelf.",
                fullTitle: "Shelf is full",
                fullBody: "The attachment finished saving but there is no room left on the shelf.",
                okButton: "OK")
        default:
            return .init(
                failedTitle: "Impossible d’ajouter la pièce jointe",
                failedBody: "Le fichier n’a pas fini d’être enregistré sur l’étagère.",
                fullTitle: "Étagère pleine",
                fullBody: "La pièce jointe a fini d’être enregistrée, mais il n’y a plus de place.",
                okButton: "OK")
        }
    }
}
