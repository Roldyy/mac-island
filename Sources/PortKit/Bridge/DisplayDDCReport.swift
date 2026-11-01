// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W2A (display). The lane owns this file.

import Foundation

/// What probing one monitor's DDC/CI channel concluded. Mirrors the ported service's private answer so the
/// verdict and the gate below are pure and testable.
enum DDCProbeOutcome: Equatable {
    /// The monitor answered a read of its luminance (VCP 0x10).
    case replied
    /// Commands are accepted but no reply ever comes.
    case writeOnly
    /// Every command was rejected: nothing reaches this display over DDC.
    case dead
}

/// One display's DDC verdict as the Settings page shows it: "pris en charge" or "non pris en charge", and why.
///
/// The probe is READ-ONLY: it asks the monitor for its current luminance (a standard DDC "get VCP feature"
/// request, which writes the request bytes to the I2C channel and reads the reply) and never sends a value.
/// Brightness values are written over DDC only to a display this verdict (or the person) cleared.
struct DDCReport: Equatable {
    enum Verdict: Equatable {
        case supported
        case notSupported
        /// The display uses the system brightness route (built-in panel, Apple display): DDC is not involved.
        case notApplicable
    }

    var verdict: Verdict
    /// French, one sentence: the reason for the verdict and, when there is one, the way out.
    var reason: String
    /// The monitor on this connection (display identity + IORegistry location), the key the choices are kept under.
    var pathKey: String?
    /// The monitor accepts commands but never answers: the person may choose to use DDC anyway.
    var canTrust: Bool = false
    /// DDC is in use because the person chose it for an unconfirmed monitor.
    var trusted: Bool = false

    /// The short label next to the display name.
    var label: String {
        switch verdict {
        case .supported: "pris en charge"
        case .notSupported: "non pris en charge"
        case .notApplicable: "réglage système"
        }
    }
}

/// The capability probe of the keyboard backlight (CoreBrightness `KeyboardBrightnessClient`, a private class):
/// it fails closed, and the page says so in French.
enum KeyboardLightProbe {
    static func summary(supported: Bool) -> (label: String, reason: String) {
        supported
            ? ("pris en charge", "Ce Mac a un rétroéclairage de clavier réglable : le niveau se lit et se règle ici.")
            : ("non pris en charge",
               "macOS n’expose pas de rétroéclairage de clavier réglable sur ce Mac (pas de clavier rétroéclairé, ou accès système indisponible). Rien n’est modifié.")
    }
}

enum DDCReports {
    /// The `UserDefaults` key of the connections the person chose to drive over DDC although the monitor never
    /// answers a read. Our own key (the upstream list of write-only paths keeps its own meaning).
    static let trustedPathsKey = "brightnessDDCTrustedPaths"

    /// What the rebuild knew about a display when it decided its route.
    enum Situation: Equatable {
        case systemRoute
        /// macOS does not expose the I2C symbols at all.
        case symbolsMissing
        /// No DDC channel in the registry belongs to this display.
        case noChannel
        /// The person chose gamma dimming for this monitor.
        case forcedSoftware(pathKey: String?)
        case probed(DDCProbeOutcome, pathKey: String?, trusted: Bool)
    }

    /// The gate between a probe and the DDC route: a value is written over DDC only after a read answered, or
    /// for an unconfirmed monitor the person chose to trust. Anything else dims the picture in software.
    static func allowsDDC(outcome: DDCProbeOutcome, trusted: Bool) -> Bool {
        switch outcome {
        case .replied: true
        case .writeOnly: trusted
        case .dead: false
        }
    }

    static func report(_ situation: Situation) -> DDCReport {
        switch situation {
        case .systemRoute:
            return DDCReport(verdict: .notApplicable,
                             reason: "Cet écran se règle par le système (écran intégré ou écran Apple), sans DDC.")
        case .symbolsMissing:
            return DDCReport(verdict: .notSupported,
                             reason: "Cette version de macOS n’expose pas l’accès DDC : l’écran est assombri par le logiciel.")
        case .noChannel:
            return DDCReport(verdict: .notSupported,
                             reason: "Aucun canal DDC n’a été trouvé pour cet écran (dock, adaptateur ou Mac sans accès DDC) : l’écran est assombri par le logiciel.")
        case .forcedSoftware(let pathKey):
            return DDCReport(verdict: .notSupported,
                             reason: "Vous avez choisi la gradation logicielle pour cet écran.", pathKey: pathKey)
        case .probed(let outcome, let pathKey, let trusted):
            switch outcome {
            case .replied:
                return DDCReport(verdict: .supported,
                                 reason: "L’écran a répondu à la lecture de sa luminosité (VCP 0x10) : la luminosité matérielle est réglée par DDC.",
                                 pathKey: pathKey)
            case .writeOnly where trusted:
                return DDCReport(verdict: .supported,
                                 reason: "L’écran accepte les commandes mais ne confirme pas sa luminosité. DDC est utilisé à votre demande.",
                                 pathKey: pathKey, canTrust: false, trusted: true)
            case .writeOnly:
                return DDCReport(verdict: .notSupported,
                                 reason: "L’écran accepte les commandes DDC mais ne répond à aucune lecture : rien ne prouve qu’il les applique. L’écran est assombri par le logiciel ; activez DDC/CI dans le menu de l’écran puis relancez le test, ou utilisez DDC quand même.",
                                 pathKey: pathKey, canTrust: pathKey != nil)
            case .dead:
                return DDCReport(verdict: .notSupported,
                                 reason: "Le canal DDC refuse les commandes (adaptateur ou dock HDMI, ou DDC/CI désactivé dans le menu de l’écran) : l’écran est assombri par le logiciel.",
                                 pathKey: pathKey)
            }
        }
    }
}
