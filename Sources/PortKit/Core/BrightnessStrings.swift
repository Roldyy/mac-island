// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Strings for the display brightness feature. Same contract as the other
/// FeatureStrings structs: memberwise init in declaration order, one static
/// per language, all in this file.
struct BrightnessFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let externalCaption: String
    let noDisplays: String
    let displayOff: String
    let turnOffDisplay: String
    let turnOnDisplay: String
    let lastDisplayCaption: String
    let switchUnavailable: String
    let switchFailed: String
    let openLidToEnable: String
    let keysToggle: String
    let keysCaption: String
    let keyStep: String
    let keyStepCaption: String
    let keyStepStandard: String
    let keyStepHalf: String
    let keyStepQuarter: String
    let osdToggle: String
    let osdCaption: String
    let displayBrightnessShortcuts: String
    let displayBrightnessShortcutCaption: String
    let displayBrightnessDecrease: String
    let displayBrightnessIncrease: String
    let keyboardLight: String
    let keyboardLightCaption: String
    let keyboardBrightnessShortcuts: String
    let keyboardBrightnessDecrease: String
    let keyboardBrightnessIncrease: String
    let softwareDimming: String
    let extendedDimming: String
    let islandPromptTitle: String
    let islandPromptMessage: String
    let islandPromptKeepOff: String
}

extension FeatureStrings {
    static func brightness(_ language: AppLanguage) -> BrightnessFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension BrightnessFeatureStrings {
    static let enUS = BrightnessFeatureStrings(
        pageTitle: "Displays",
        hubDescription: "Brightness and power controls for every display",
        enable: "Control displays",
        enableCaption: "Brightness and on or off controls for the built-in and external displays, here and in the menu bar panel.",
        externalCaption: "External displays are adjusted through the same protocol as their own buttons. When the connection cannot carry it, as with HDMI adapters, the slider dims the picture instead, so brightness control works either way.",
        noDisplays: "No display found.",
        displayOff: "Off",
        turnOffDisplay: "Turn off display",
        turnOnDisplay: "Turn on display",
        lastDisplayCaption: "At least one display must stay on.",
        switchUnavailable: "Display switching is unavailable on this Mac.",
        switchFailed: "Could not change this display.",
        openLidToEnable: "Open the lid to turn on the built-in display.",
        keysToggle: "Brightness keys follow the pointer",
        keysCaption: "The keyboard brightness keys change the display under the pointer.",
        keyStep: "Brightness key steps",
        keyStepCaption: "Smaller steps for each press of the brightness keys and display brightness shortcuts.",
        keyStepStandard: "Standard",
        keyStepHalf: "Half steps",
        keyStepQuarter: "Quarter steps",
        osdToggle: "Show brightness when adjusting",
        osdCaption: "Shows the brightness percentage when you use the brightness keys or sliders.",
        displayBrightnessShortcuts: "Use display brightness shortcuts",
        displayBrightnessShortcutCaption: "Shortcuts adjust the primary display, or the display under the pointer when pointer following is on.",
        displayBrightnessDecrease: "Decrease display brightness",
        displayBrightnessIncrease: "Increase display brightness",
        keyboardLight: "Keyboard light",
        keyboardLightCaption: "Turns the keyboard backlight on or off.",
        keyboardBrightnessShortcuts: "Use keyboard brightness shortcuts",
        keyboardBrightnessDecrease: "Decrease keyboard brightness",
        keyboardBrightnessIncrease: "Increase keyboard brightness",
        softwareDimming: "Dim the picture",
        extendedDimming: "Extra dimming",
        islandPromptTitle: "Show brightness in the Dynamic Island?",
        islandPromptMessage: "The Dynamic Island shows brightness changes only while “Control displays” is on in Displays settings.",
        islandPromptKeepOff: "Keep Off"
    )

    static let fr = BrightnessFeatureStrings(
        pageTitle: "Écrans",
        hubDescription: "Luminosité et alimentation de tous les écrans",
        enable: "Contrôler les écrans",
        enableCaption: "Contrôles de luminosité et d’alimentation pour l’écran intégré et les moniteurs externes, ici et dans le panneau de la barre des menus.",
        externalCaption: "Les moniteurs externes sont réglés par le même protocole que leurs propres boutons. Quand la connexion ne le transmet pas, comme avec les adaptateurs HDMI, le curseur assombrit l’image, le réglage fonctionne donc dans tous les cas.",
        noDisplays: "Aucun écran détecté.",
        displayOff: "Éteint",
        turnOffDisplay: "Éteindre l’écran",
        turnOnDisplay: "Allumer l’écran",
        lastDisplayCaption: "Au moins un écran doit rester allumé.",
        switchUnavailable: "Le contrôle d’alimentation des écrans n’est pas disponible sur ce Mac.",
        switchFailed: "Impossible de modifier cet écran.",
        openLidToEnable: "Ouvrez le couvercle pour allumer l’écran intégré.",
        keysToggle: "Les touches de luminosité suivent le pointeur",
        keysCaption: "Les touches de luminosité du clavier règlent l’écran où se trouve le pointeur.",
        keyStep: "Pas des touches de luminosité",
        keyStepCaption: "Des pas plus fins à chaque pression sur les touches de luminosité et les raccourcis de luminosité de l’écran.",
        keyStepStandard: "Standard",
        keyStepHalf: "Demi-pas",
        keyStepQuarter: "Quart de pas",
        osdToggle: "Afficher la luminosité pendant le réglage",
        osdCaption: "Affiche le pourcentage de luminosité avec les touches ou les curseurs de luminosité.",
        displayBrightnessShortcuts: "Utiliser les raccourcis de luminosité de l’écran",
        displayBrightnessShortcutCaption: "Les raccourcis règlent l’écran principal ou celui sous le pointeur lorsque le suivi du pointeur est activé.",
        displayBrightnessDecrease: "Réduire la luminosité de l’écran",
        displayBrightnessIncrease: "Augmenter la luminosité de l’écran",
        keyboardLight: "Éclairage du clavier",
        keyboardLightCaption: "Allume ou éteint l’éclairage du clavier.",
        keyboardBrightnessShortcuts: "Utiliser les raccourcis de luminosité du clavier",
        keyboardBrightnessDecrease: "Réduire la luminosité du clavier",
        keyboardBrightnessIncrease: "Augmenter la luminosité du clavier",
        softwareDimming: "Assombrir l’image",
        extendedDimming: "Assombrissement supplémentaire",
        islandPromptTitle: "Afficher la luminosité dans la Dynamic Island ?",
        islandPromptMessage: "La Dynamic Island n’affiche les changements de luminosité que lorsque « Contrôler les écrans » est activé dans les réglages Écrans.",
        islandPromptKeepOff: "Laisser désactivé"
    )

}
