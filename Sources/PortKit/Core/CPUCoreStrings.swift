// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct CPUCoreFeatureStrings {
    let title: String
    let coreFormat: String
    let hint: String
    let superCores: String
    let performanceCores: String
    let efficiencyCores: String
    let apps: String
    /// Settings switch for the per-core bars under CPU.
    let perCore: String
}

extension FeatureStrings {
    static func cpuCores(_ language: AppLanguage) -> CPUCoreFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension CPUCoreFeatureStrings {
    static let enUS = CPUCoreFeatureStrings(
        title: "Logical CPU cores",
        coreFormat: "Core %d",
        hint: "Each bar is one logical core. Its fill height shows utilization, not remaining performance.",
        superCores: "Super",
        performanceCores: "Performance",
        efficiencyCores: "Efficiency",
        apps: "Apps using CPU",
        perCore: "Per core"
    )

    static let fr = CPUCoreFeatureStrings(
        title: "Cœurs logiques du CPU",
        coreFormat: "Cœur %d",
        hint: "Chaque barre représente un cœur logique. La hauteur du remplissage indique son utilisation.",
        superCores: "Super",
        performanceCores: "Performance",
        efficiencyCores: "Efficacité",
        apps: "Apps utilisant le CPU",
        perCore: "Par cœur"
    )

}
