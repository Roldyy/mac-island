// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct ConnectedDevicesFeatureStrings {
    let title: String
    let hubDescription: String
    let noDevices: String
    let unnamedDevice: String
    let menuBarLabel: String
    let oneConnected: String
    let devicesConnectedFormat: String

    func formattedCount(_ count: Int) -> String {
        if count == 1 {
            return oneConnected
        }
        return String(format: devicesConnectedFormat, count)
    }
}

extension FeatureStrings {
    static func connectedDevices(_ language: AppLanguage) -> ConnectedDevicesFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

private extension ConnectedDevicesFeatureStrings {
    static let enUS = ConnectedDevicesFeatureStrings(
        title: "Connected Devices",
        hubDescription: "Count connected external USB peripherals",
        noDevices: "No external devices connected",
        unnamedDevice: "USB Device",
        menuBarLabel: "USB",
        oneConnected: "1 device connected",
        devicesConnectedFormat: "%d devices connected"
    )

    static let fr = ConnectedDevicesFeatureStrings(
        title: "Appareils connectés",
        hubDescription: "Compter les périphériques USB externes connectés",
        noDevices: "Aucun appareil externe connecté",
        unnamedDevice: "Appareil USB",
        menuBarLabel: "USB",
        oneConnected: "1 appareil connecté",
        devicesConnectedFormat: "%d appareils connectés"
    )

}
