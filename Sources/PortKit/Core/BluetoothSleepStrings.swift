// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Strings for the Bluetooth on sleep feature. Same contract as the other
/// FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct BluetoothSleepStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let restoreToggle: String
    let restoreCaption: String
    let unsupported: String
}

extension FeatureStrings {
    static func bluetoothSleep(_ language: AppLanguage) -> BluetoothSleepStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension BluetoothSleepStrings {
    static let enUS = BluetoothSleepStrings(
        pageTitle: "Bluetooth on sleep",
        hubDescription: "Switches Bluetooth off while the Mac sleeps, so headphones in a bag stop connecting to it.",
        enable: "Turn Bluetooth off when the Mac sleeps",
        enableCaption: "Bluetooth already off before sleep is left alone and stays off on wake.",
        restoreToggle: "Turn Bluetooth back on when the Mac wakes",
        restoreCaption: "Only when Mac Island was the one that switched it off.",
        unsupported: "This Mac has no Bluetooth controller."
    )

    static let fr = BluetoothSleepStrings(
        pageTitle: "Bluetooth en veille",
        hubDescription: "Coupe le Bluetooth pendant que le Mac dort, pour que les écouteurs rangés dans un sac cessent de s’y connecter.",
        enable: "Couper le Bluetooth quand le Mac se met en veille",
        enableCaption: "Un Bluetooth déjà coupé avant la veille n’est pas touché et reste coupé au réveil.",
        restoreToggle: "Rallumer le Bluetooth au réveil du Mac",
        restoreCaption: "Uniquement si c’est Mac Island qui l’a coupé.",
        unsupported: "Ce Mac n’a pas de contrôleur Bluetooth."
    )

}
