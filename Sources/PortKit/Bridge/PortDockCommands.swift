// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import AppKit
import Foundation

/// One command of the ported features, as the island's extra dock lists it. Plain values: PortKit cannot see
/// ShellKit's `DockCommand`, so the app delegate turns each of these into one (same id, same closures).
public struct PortDockCommand {
    public enum Category: String, Sendable { case capture, tools, system }

    public let id: String
    public let title: String
    public let systemImage: String
    public let category: Category
    public let keywords: [String]
    /// Non-nil: the command changes or discards something, so the dock asks this question before running it.
    public let confirmation: String?
    /// The command acts on another app or on the screen: the host closes the island first and runs it a moment later.
    public let closesIsland: Bool
    public let isOn: (@MainActor () -> Bool)?
    /// Why it cannot run now (feature off, permission missing, busy), nil when it can. Never prompts, never asks.
    public let unavailableReason: @MainActor () -> String?
    public let run: @MainActor () -> Void
}

/// The ported features' entry points, wired to the services' own doors. Nothing here starts a service or asks for a
/// permission: `unavailableReason` reads the registry's verdict and the last permission reading, `run` calls the same
/// function the feature's own shortcut calls.
public enum PortDockCommands {
    /// Lent by the app delegate (PortKit cannot see `ClipboardFeature` or the registry): is OUR clipboard feature running,
    /// clear what it keeps (the pinned stay), paste as plain text. The ported clipboard services are never started
    /// (`ClipboardLane`), so `AppFeature.clipboardHistory` / `.pastePlain` answer "off" forever and must not gate these.
    @MainActor public static var clipboardIsOn: @MainActor () -> Bool = { false }
    @MainActor public static var clearClipboardUnpinned: @MainActor () -> Void = {}
    @MainActor public static var pastePlainFromClipboard: @MainActor () -> Void = {}

    private static func off(_ title: String) -> String { "« \(title) » est désactivée. Active-la dans Fonctionnalités." }

    private static let screenRecordingMissing = "Autorisation « Enregistrement de l'écran » manquante. Ouvre les Réglages pour l'accorder."

    /// Feature on, then Screen Recording granted, then no other capture on screen.
    @MainActor private static func captureReason(_ feature: AppFeature, _ title: String, allowBusy: Bool = false) -> String? {
        guard feature.isAvailable else { return off(title) }
        guard PortHost.permissionState.value.screenRecording else { return screenRecordingMissing }
        if !allowBusy, ScreenshotSelectionController.isSessionOnScreen || ScreenCaptureService.shared.hasActiveSession {
            return "Une capture est déjà en cours."
        }
        return nil
    }

    /// The ids of every command, in order. Fixed: tests pin them and a saved dock refers to them.
    public static let ids = [
        "port.capture.scrolling", "port.capture.recent", "port.record", "port.ocr", "port.color",
        "port.pasteplain", "port.micmute", "port.launcher", "port.radial",
        "port.clipboard.clearUnpinned", "port.timer.start", "port.timer.stop",
    ]

    @MainActor public static func all() -> [PortDockCommand] {
        [
            PortDockCommand(
                id: "port.capture.scrolling", title: "Capture défilante", systemImage: "arrow.up.and.down.text.horizontal",
                category: .capture, keywords: ["scroll", "page longue", "défilement"], confirmation: nil, closesIsland: true, isOn: nil,
                unavailableReason: { captureReason(.screenshot, "Capture d'écran") },
                run: { PortScreenshot.beginScrollingCapture() }),
            PortDockCommand(
                id: "port.capture.recent", title: "Captures récentes", systemImage: "photo.stack", category: .capture,
                keywords: ["historique", "dernières captures"], confirmation: nil, closesIsland: true, isOn: nil,
                unavailableReason: { AppFeature.screenshot.isAvailable ? nil : off("Capture d'écran") },
                run: { PortScreenshot.showRecentCaptures() }),
            PortDockCommand(
                id: "port.record", title: "Enregistrer l'écran", systemImage: "record.circle", category: .capture,
                keywords: ["vidéo", "screen recording", "enregistrement"], confirmation: nil, closesIsland: true,
                isOn: { ScreenRecorderService.shared.hasActiveCapture },
                unavailableReason: { captureReason(.screenRecorder, "Enregistreur d'écran", allowBusy: true) },
                run: { ScreenCaptureService.shared.capture(initial: .recording) }),
            PortDockCommand(
                id: "port.ocr", title: "Copier le texte de l'écran", systemImage: "text.viewfinder", category: .capture,
                keywords: ["ocr", "reconnaissance de texte", "qr"], confirmation: nil, closesIsland: true, isOn: nil,
                unavailableReason: { captureReason(.screenOCR, "Texte à l'écran") },
                run: { ScreenTextService.shared.capture() }),
            PortDockCommand(
                id: "port.color", title: "Pipette de couleur", systemImage: "eyedropper", category: .capture,
                keywords: ["couleur", "color picker", "hex"], confirmation: nil, closesIsland: true, isOn: nil,
                // The native sampler needs no capture permission, so only the feature and a free screen count.
                unavailableReason: {
                    guard AppFeature.colorPicker.isAvailable else { return off("Pipette de couleur") }
                    return ScreenshotSelectionController.isSessionOnScreen || ScreenCaptureService.shared.hasActiveSession
                        ? "Une capture est déjà en cours." : nil
                },
                run: { ColorSamplerService.shared.pick() }),
            PortDockCommand(
                id: "port.pasteplain", title: "Coller sans mise en forme", systemImage: "doc.plaintext", category: .tools,
                keywords: ["texte brut", "plain paste", "coller"], confirmation: nil, closesIsland: true, isOn: nil,
                unavailableReason: {
                    guard clipboardIsOn() else { return off("Presse-papiers") }
                    return PortHost.permissionState.value.accessibility
                        ? nil : "Autorisation « Accessibilité » manquante. Ouvre les Réglages pour l'accorder."
                },
                run: { pastePlainFromClipboard() }),
            PortDockCommand(
                id: "port.micmute", title: "Couper le micro", systemImage: "mic.slash", category: .tools,
                keywords: ["micro", "microphone", "mute", "silence"], confirmation: nil, closesIsland: false,
                isOn: { MicMuteService.shared.isMuted },
                unavailableReason: { AppFeature.micMute.isAvailable ? nil : off("Couper le micro") },
                run: { MicMuteService.shared.toggle() }),
            PortDockCommand(
                id: "port.launcher", title: "Lanceur rapide", systemImage: "magnifyingglass.circle", category: .tools,
                keywords: ["launcher", "ouvrir une app", "raccourcis"], confirmation: nil, closesIsland: true, isOn: nil,
                unavailableReason: { AppFeature.quickLauncher.isAvailable ? nil : off("Lanceur rapide") },
                run: { QuickLauncherService.shared.toggle() }),
            PortDockCommand(
                id: "port.radial", title: "Menu radial", systemImage: "circle.hexagongrid", category: .tools,
                keywords: ["roue", "radial menu", "cercle"], confirmation: nil, closesIsland: true, isOn: nil,
                unavailableReason: {
                    guard AppFeature.radialMenu.isAvailable else { return off("Menu radial") }
                    return PortHost.defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
                        ? nil : "Le menu radial est éteint. Allume-le dans ses Réglages."
                },
                run: { RadialMenuService.shared.presentPreview() }),
            PortDockCommand(
                id: "port.clipboard.clearUnpinned", title: "Vider le presse-papiers (hors épinglés)",
                systemImage: "trash", category: .tools, keywords: ["effacer", "historique", "supprimer", "clipboard"],
                confirmation: "Supprimer tous les éléments non épinglés de l'historique du presse-papiers ? Les épinglés restent.",
                closesIsland: false, isOn: nil,
                unavailableReason: { clipboardIsOn() ? nil : off("Presse-papiers") },
                run: { clearClipboardUnpinned() }),
            PortDockCommand(
                id: "port.timer.start", title: "Minuteur de 25 minutes", systemImage: "timer", category: .tools,
                keywords: ["minuteur", "chrono", "timer", "compte à rebours"], confirmation: nil, closesIsland: false,
                isOn: { NotchTimerService.shared.session.isRunning },
                unavailableReason: {
                    guard NotchTimerSupport.isEnabled() else { return off("Minuteur") }
                    return NotchTimerService.shared.session.hasSession ? "Un minuteur est déjà en cours." : nil
                },
                run: { NotchTimerService.shared.start(mode: .timer, minutes: 25) }),
            PortDockCommand(
                id: "port.timer.stop", title: "Arrêter le minuteur", systemImage: "timer.circle", category: .tools,
                keywords: ["minuteur", "stop", "annuler"],
                confirmation: "Arrêter le minuteur en cours ? Le temps écoulé est perdu.", closesIsland: false, isOn: nil,
                unavailableReason: {
                    guard NotchTimerSupport.isEnabled() else { return off("Minuteur") }
                    return NotchTimerService.shared.session.hasSession ? nil : "Aucun minuteur en cours."
                },
                run: { NotchTimerService.shared.cancel() }),
        ]
    }
}
