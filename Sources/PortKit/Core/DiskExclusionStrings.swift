// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct DiskExclusionStrings {
    let listTitle: String
    let addButton: String
    let otherDrive: String
    let removeButton: String
    let customPlaceholder: String
    let caption: String
}

extension FeatureStrings {
    static func diskExclusions(_ language: AppLanguage) -> DiskExclusionStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension DiskExclusionStrings {
    static let enUS = DiskExclusionStrings(
        listTitle: "Excluded drives",
        addButton: "Add drive…",
        otherDrive: "Other drive name…",
        removeButton: "Remove",
        customPlaceholder: "Drive or volume name",
        caption: "Drives in this list are never unmounted when using Eject all disks."
    )

    static let fr = DiskExclusionStrings(
        listTitle: "Disques exclus",
        addButton: "Ajouter un disque…",
        otherDrive: "Autre nom de disque…",
        removeButton: "Retirer",
        customPlaceholder: "Nom du disque ou volume",
        caption: "Les disques de cette liste ne sont jamais éjectés lors de l’éjection de tous les disques."
    )

}
