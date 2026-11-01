// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct FanControlFeatureStrings {
    let title: String
    let hubDescription: String
    let showInPanel: String
    let settingsCaption: String
    let fanNameFormat: String
    let rpmFormat: String
    let allowControl: String
    let approvalCaption: String
    let openSettings: String
    let noFans: String
    let unsupported: String
    let alreadyControlled: String
    let failed: String
    let safetyCaption: String
    let safetyStopped: String
    let menuBarTitle: String
    let systemControl: String
    let manualControl: String
    let customCurve: String
    let mode: String
    let coolingIntensity: String
    let currentRPMFormat: String
    let targetRPMFormat: String
    let applyManual: String
    let applyCurve: String
    let returnToSystem: String
    let temperatureUnavailable: String
    let curveUnavailable: String
    let sensor: String
    let temperature: String
    let fanSpeed: String
    let addPoint: String
    let addSensor: String
    let removePoint: String
    let removeSensor: String
    let curveGraph: String
    let averageSoC: String
    let hottestSoC: String
    let averageCPU: String
    let hottestCPU: String
    let hottestGPU: String
    let helperUnavailable: String
    let resumeAfterRestart: String
}

extension FeatureStrings {
    static func fanControl(_ language: AppLanguage) -> FanControlFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension FanControlFeatureStrings {
    static let enUS = FanControlFeatureStrings(
        title: "Fan Control",
        hubDescription: "Control fans manually or with temperature curves while seeing live and target RPM",
        showInPanel: "Show Fan Control in the panel",
        settingsCaption: "Adds manual fan speeds and temperature curves to the menu bar panel.",
        fanNameFormat: "Fan %d",
        rpmFormat: "%d RPM",
        allowControl: "Allow fan control",
        approvalCaption: "Allow Mac Island in Login Items to use the protected fan controller.",
        openSettings: "Open System Settings",
        noFans: "This Mac has no controllable fan.",
        unsupported: "Fan control is not available on this Mac.",
        alreadyControlled: "Another process is controlling the fans. Return it to system control first.",
        failed: "The fans returned to system control because the requested control could not be verified.",
        safetyCaption: "Control stays active until you return to System. It returns automatically if the app disconnects, the Mac sleeps, sensor readings fail or thermal pressure rises.",
        safetyStopped: "Returned to system control because fan control was interrupted.",
        menuBarTitle: "Fan speed",
        systemControl: "System",
        manualControl: "Manual",
        customCurve: "Curve",
        mode: "Control mode",
        coolingIntensity: "Fan speed",
        currentRPMFormat: "Current %d RPM",
        targetRPMFormat: "Target %d RPM",
        applyManual: "Apply manual control",
        applyCurve: "Apply fan curve",
        returnToSystem: "Use system control",
        temperatureUnavailable: "The selected temperature sensor stopped responding. Fan control returned to System.",
        curveUnavailable: "A selected temperature sensor is not available on this Mac.",
        sensor: "Temperature sensor",
        temperature: "Temperature",
        fanSpeed: "Fan speed",
        addPoint: "Add point",
        addSensor: "Add sensor",
        removePoint: "Remove point",
        removeSensor: "Remove sensor",
        curveGraph: "Temperature and fan speed curve",
        averageSoC: "Average SoC",
        hottestSoC: "Hottest SoC",
        averageCPU: "Average CPU",
        hottestCPU: "Hottest CPU",
        hottestGPU: "Hottest GPU",
        helperUnavailable: "The protected fan controller is unavailable. Allow Mac Island in Login Items, then try again.",
        resumeAfterRestart: "Resume after restart or sleep"
    )

    static let fr = FanControlFeatureStrings(
        title: "Contrôle des ventilateurs",
        hubDescription: "Contrôle manuel ou par courbes de température avec vitesses réelle et cible",
        showInPanel: "Afficher le contrôle des ventilateurs dans le panneau",
        settingsCaption: "Ajoute les vitesses manuelles et les courbes de température au panneau.",
        fanNameFormat: "Ventilateur %d",
        rpmFormat: "%d tr/min",
        allowControl: "Autoriser le contrôle",
        approvalCaption: "Autorisez Mac Island dans Ouverture pour utiliser le contrôle protégé des ventilateurs.",
        openSettings: "Ouvrir Réglages Système",
        noFans: "Ce Mac ne possède aucun ventilateur contrôlable.",
        unsupported: "Le contrôle des ventilateurs n’est pas disponible sur ce Mac.",
        alreadyControlled: "Un autre processus contrôle les ventilateurs. Rendez-les d’abord au système.",
        failed: "Les ventilateurs ont été rendus au système car le contrôle demandé n’a pas pu être vérifié.",
        safetyCaption: "Le contrôle reste actif jusqu’au retour à Système. Il est rendu automatiquement si l’app se déconnecte, si le Mac veille, si les capteurs échouent ou si la pression thermique augmente.",
        safetyStopped: "Le contrôle a été rendu au système car le contrôle des ventilateurs a été interrompu.",
        menuBarTitle: "Vitesse des ventilateurs",
        systemControl: "Système",
        manualControl: "Manuel",
        customCurve: "Courbe",
        mode: "Mode de contrôle",
        coolingIntensity: "Vitesse des ventilateurs",
        currentRPMFormat: "Actuelle %d tr/min",
        targetRPMFormat: "Cible %d tr/min",
        applyManual: "Appliquer le contrôle manuel",
        applyCurve: "Appliquer la courbe",
        returnToSystem: "Utiliser le contrôle du système",
        temperatureUnavailable: "Le capteur de température choisi ne répond plus. Le contrôle a été rendu au Système.",
        curveUnavailable: "Un capteur de température sélectionné n’est pas disponible sur ce Mac.",
        sensor: "Capteur de température",
        temperature: "Température",
        fanSpeed: "Vitesse",
        addPoint: "Ajouter un point",
        addSensor: "Ajouter un capteur",
        removePoint: "Supprimer le point",
        removeSensor: "Supprimer le capteur",
        curveGraph: "Courbe de température et de vitesse",
        averageSoC: "Moyenne du SoC",
        hottestSoC: "SoC le plus chaud",
        averageCPU: "Moyenne du CPU",
        hottestCPU: "CPU le plus chaud",
        hottestGPU: "GPU le plus chaud",
        helperUnavailable: "Le contrôleur protégé des ventilateurs est indisponible. Autorisez Mac Island dans Ouverture, puis réessayez.",
        resumeAfterRestart: "Reprendre après un redémarrage ou la veille"
    )

}
