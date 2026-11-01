// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct SuperKeyStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let modifierKeysNote: String
    let sourceKey: String
    let capsLockKey: String
    let rightKeyFormat: String
    let holdHint: String
    let soloSection: String
    let soloCaption: String
    let soloNothing: String
    let soloCapsLock: String
    let soloEscape: String
    let activeNow: String
    let panelCaptionFormat: String
    let manageButton: String
    let soloInputSource: String
    let mappingForeignMapping: String
    let mappingSystemRefused: String
    let keyboardTapRefused: String

    /// What to show when the key mapping was refused. Every refusal names one
    /// thing to change; none of them is visible in the key itself.
    func mappingFailure(_ failure: SuperKeyMappingFailure) -> String {
        switch failure {
        case .foreignMapping: return mappingForeignMapping
        case .systemRefused: return mappingSystemRefused
        case .keyboardTapRefused: return keyboardTapRefused
        }
    }
}

extension FeatureStrings {
    static func superKey(_ language: AppLanguage) -> SuperKeyStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension SuperKeyStrings {
    func sourceLabel(_ source: SuperKeySource) -> String {
        guard let symbol = source.symbol else { return capsLockKey }
        return String(format: rightKeyFormat, symbol)
    }

    static let enUS = SuperKeyStrings(
        pageTitle: "Super key",
        hubDescription: "Turns one key into the modifier combination you choose.",
        enableToggle: "Use this key as the super key",
        enableCaption: "Hold it and press any key. Choose one or more modifiers below.",
        modifierKeysNote: "Keep this key set to its default action in System Settings › Keyboard › Modifier Keys.",
        sourceKey: "Key to hold",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "Right %@",
        holdHint: "Hold",
        soloSection: "A tap on its own",
        soloCaption: "What a quick tap does when no other key is pressed.",
        soloNothing: "Nothing",
        soloCapsLock: "Turn capitals on and off",
        soloEscape: "Press Escape",
        activeNow: "Working now",
        panelCaptionFormat: "%1$@ holds %2$@.",
        manageButton: "Set up…",
        soloInputSource: "Switch input source; hold for Caps Lock",
        mappingForeignMapping: "Another app’s key mapping uses the selected key. Remove it in that app: quitting it is not enough.",
        mappingSystemRefused: "macOS refused the key mapping. Reconnect the keyboard or restart the Mac, then switch this on again.",
        keyboardTapRefused: "macOS would not let Mac Island watch the keyboard. Turn Mac Island off and on in System Settings › Privacy & Security › Accessibility, then switch this on again."
    )

    static let fr = SuperKeyStrings(
        pageTitle: "Touche super",
        hubDescription: "Transforme une touche en la combinaison de modificateurs de votre choix.",
        enableToggle: "Utiliser cette touche comme touche Super",
        enableCaption: "Maintenez-la et appuyez sur n’importe quelle touche. Choisissez un ou plusieurs modificateurs ci-dessous.",
        modifierKeysNote: "Conservez l’action par défaut de cette touche dans Réglages Système › Clavier › Touches de modification.",
        sourceKey: "Touche à maintenir",
        capsLockKey: "Verr. Maj",
        rightKeyFormat: "%@ droite",
        holdHint: "Maintenez",
        soloSection: "Un appui seul",
        soloCaption: "Ce que fait un appui rapide quand aucune autre touche n’est pressée.",
        soloNothing: "Rien",
        soloCapsLock: "Active et désactive les majuscules",
        soloEscape: "Appuie sur Échap",
        activeNow: "Actif maintenant",
        panelCaptionFormat: "%1$@ maintient %2$@.",
        manageButton: "Configurer…",
        soloInputSource: "Changer de source d’entrée\u{00A0}; maintenir pour Verr. Maj",
        mappingForeignMapping: "Le remappage d’une autre app utilise la touche sélectionnée. Supprimez-le dans cette app\u{00A0}: la quitter ne suffit pas.",
        mappingSystemRefused: "macOS a refusé le remappage. Rebranchez le clavier ou redémarrez le Mac, puis réactivez ceci.",
        keyboardTapRefused: "macOS n’a pas autorisé Mac Island à surveiller le clavier. Désactivez puis réactivez Mac Island dans Réglages Système › Confidentialité et sécurité › Accessibilité, puis réactivez ceci."
    )

}
