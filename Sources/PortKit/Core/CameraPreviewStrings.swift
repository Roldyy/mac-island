// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Localized strings for the camera preview mirror.
struct CameraPreviewFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let cameraMenuLabel: String
    let deniedMessage: String
    let noCameraMessage: String
    let permName: String
    let permExplain: String
}

extension FeatureStrings {
    static func cameraPreview(_ language: AppLanguage) -> CameraPreviewFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension CameraPreviewFeatureStrings {
    static let enUS = CameraPreviewFeatureStrings(
        pageTitle: "Camera preview",
        hubDescription: "Opens a floating mirror with your camera",
        panelCaption: "Check how you look before a call",
        openButton: "Open preview",
        cameraMenuLabel: "Camera",
        deniedMessage: "Camera access for Mac Island is turned off in System Settings.",
        noCameraMessage: "No camera detected",
        permName: "Camera",
        permExplain: "Shows your camera only in the preview window, so you can check how you look before a call. Nothing is recorded or leaves your Mac."
    )

    static let fr = CameraPreviewFeatureStrings(
        pageTitle: "Aperçu de la caméra",
        hubDescription: "Ouvre un miroir flottant avec votre caméra",
        panelCaption: "Vérifiez votre apparence avant un appel",
        openButton: "Ouvrir l’aperçu",
        cameraMenuLabel: "Caméra",
        deniedMessage: "L’accès à la caméra pour Mac Island est désactivé dans Réglages Système.",
        noCameraMessage: "Aucune caméra détectée",
        permName: "Caméra",
        permExplain: "Affiche votre caméra uniquement dans la fenêtre d’aperçu, pour vérifier votre apparence avant un appel. Rien n’est enregistré et rien ne quitte votre Mac."
    )

}
