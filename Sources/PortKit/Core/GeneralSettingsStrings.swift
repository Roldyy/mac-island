// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Plain-language copy for the General page: one short line per control and
/// one per panel section, so the page explains itself without paragraphs.
struct GeneralSettingsStrings {
    let pageDescription: String
    let appearanceCaption: String
    let launchAtLoginCaption: String
    let liquidGlassCaption: String
    let liquidGlassOtherWindows: String
    let panelIntro: String
    let panelReorderHint: String
    let menuBarIconTitle: String
    let menuBarIconCaption: String
    let menuBarIconOther: String
    let menuBarIconOtherCaption: String
    let menuBarIconUnknown: String
    let menuBarIconReset: String
    let iconMissingTitle: String
    let iconMissingCaption: String
    let sectionKeepAwake: String
    let sectionDisplays: String
    let sectionMixer: String
    let sectionSystem: String
    let sectionNetwork: String
    let sectionDisks: String
    let sectionPower: String
    let sectionFanControl: String
    let sectionUtilities: String
    let sectionControls: String
    let sectionToggles: String
}

extension FeatureStrings {
    static func generalSettings(_ language: AppLanguage) -> GeneralSettingsStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension GeneralSettingsStrings {
    static let enUS = GeneralSettingsStrings(
        pageDescription: "How Mac Island starts, how it looks and what its menu bar panel shows.",
        appearanceCaption: "Applies to Mac Island’s own windows and panels, not to the whole Mac.",
        launchAtLoginCaption: "Opens by itself every time you turn on your Mac.",
        liquidGlassCaption: "See-through, glass-like panels.",
        liquidGlassOtherWindows: "Other windows and panels",
        panelIntro: "Click Mac Island’s icon in the menu bar to open the panel. Its tabs appear in this order.",
        panelReorderHint: "Drag to reorder. Switch off anything you don’t need.",
        menuBarIconTitle: "Menu bar icon",
        menuBarIconCaption: "Choose the icon Mac Island shows in the menu bar.",
        menuBarIconOther: "Other symbol",
        menuBarIconOtherCaption: "Type the name of any SF Symbol. Leave it empty to use the Mac Island icon.",
        menuBarIconUnknown: "This Mac has no symbol with that name.",
        menuBarIconReset: "Use the Mac Island icon",
        iconMissingTitle: "Can’t find the icon?",
        iconMissingCaption: "A crowded menu bar can hide it, especially on Macs with a notch.",
        sectionKeepAwake: "Keeps your Mac awake for as long as you want.",
        sectionDisplays: "Brightness of your displays.",
        sectionMixer: "Volume of each app, one slider each.",
        sectionSystem: "Processor, graphics and memory at a glance.",
        sectionNetwork: "Internet speed and which apps are using it.",
        sectionDisks: "Free space and disk activity.",
        sectionPower: "Battery, charging and power use.",
        sectionFanControl: "Fan speeds and your own fan curve.",
        sectionUtilities: "Screenshots, cleaner, updates and other tools.",
        sectionControls: "Switches for mouse, keyboard and window features.",
        sectionToggles: "One-click actions like dark mode and muting the mic."
    )

    static let fr = GeneralSettingsStrings(
        pageDescription: "Comment Mac Island démarre, à quoi il ressemble et ce que montre le panneau de la barre des menus.",
        appearanceCaption: "Ne concerne que les fenêtres et panneaux de Mac Island, pas tout le Mac.",
        launchAtLoginCaption: "S’ouvre tout seul à chaque démarrage du Mac.",
        liquidGlassCaption: "Panneaux translucides, à l’aspect de verre.",
        liquidGlassOtherWindows: "Autres fenêtres et panneaux",
        panelIntro: "Cliquez sur l’icône de Mac Island dans la barre des menus pour ouvrir le panneau. Ses onglets apparaissent dans cet ordre.",
        panelReorderHint: "Glissez pour réordonner. Désactivez ce dont vous n’avez pas besoin.",
        menuBarIconTitle: "Icône de la barre des menus",
        menuBarIconCaption: "Choisissez l’icône que Mac Island affiche dans la barre des menus.",
        menuBarIconOther: "Autre symbole",
        menuBarIconOtherCaption: "Saisissez le nom de n’importe quel SF Symbol. Laissez vide pour utiliser l’icône de Mac Island.",
        menuBarIconUnknown: "Ce Mac n’a aucun symbole portant ce nom.",
        menuBarIconReset: "Utiliser l’icône de Mac Island",
        iconMissingTitle: "Vous ne trouvez pas l’icône\u{00A0}?",
        iconMissingCaption: "Une barre des menus encombrée peut la masquer, surtout sur les Mac avec encoche.",
        sectionKeepAwake: "Garde le Mac éveillé aussi longtemps que vous voulez.",
        sectionDisplays: "Luminosité de vos écrans.",
        sectionMixer: "Volume de chaque app, avec un curseur pour chacune.",
        sectionSystem: "Processeur, graphismes et mémoire en un coup d’œil.",
        sectionNetwork: "Vitesse d’Internet et apps qui l’utilisent.",
        sectionDisks: "Espace libre et activité des disques.",
        sectionPower: "Batterie, charge et consommation d’énergie.",
        sectionFanControl: "Vitesse des ventilateurs et votre propre courbe.",
        sectionUtilities: "Captures d’écran, nettoyage, mises à jour et autres outils.",
        sectionControls: "Interrupteurs pour les fonctions de souris, clavier et fenêtres.",
        sectionToggles: "Actions en un clic, comme le mode sombre et la coupure du micro."
    )

}
