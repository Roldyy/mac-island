// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W4C (copy text from screen / OCR, colour picker, camera preview, QR). The lane owns this file.

import AppKit
import IslandKit
import IslandUI
import SwiftUI

// MARK: - Lane

/// Binds the three ported capture tools: `screenOCR` (page 16), `colorPicker` (page 17) and `cameraPreview`
/// (page 10). Called once at launch by `PortLanes`, before the registry exists. Nothing here starts a service.
///
/// What the registry does, all through `Runtime` so tests never touch Vision, the capture surface or a camera:
/// - OCR and the colour picker share ONE capture chooser (`ScreenCaptureService`, the surface the screenshot lane also
///   uses): start registers the tool's own global shortcut (only when the user turned it on), stop releases it and
///   cancels a chooser that was open on the tool. The chooser is re-synced, never suspended, so a sibling tool keeps
///   its shortcut. OCR needs Screen Recording (the registry holds it back until the monitor sees the grant, and
///   restarts it on the grant). The colour picker needs nothing: without Screen Recording it falls back to the
///   system sampler (`NSColorSampler`), the permission-free path.
/// - The camera: start arms the preview's shortcut and the camera safety below; stop (switch off, kill switch, safe
///   mode, quarantine) closes the preview, which releases the capture session. Quitting the app does the same,
///   synchronously.
///
/// Camera guarantees (`CameraSafety`): the capture session exists only while the preview is on screen; every way of
/// closing the preview (Escape, a click elsewhere, switching app, the registry) releases it; the island shows an
/// always-on indicator for as long as a session exists; and a preview nobody touches for 5 minutes closes itself.
///
/// Nothing here prompts. The clicks on "Autoriser" are: the preview panel's own button (`requestAccessByClick`, the
/// only camera prompt site), the camera page's button (`Permissions.requestCamera`), and the Screen Recording
/// card the registry puts on top of the OCR page (`UserPermissionRequest`). The page rows below only read state and
/// open System Settings.
enum CaptureToolsLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        /// Registers the shortcut of each capture tool that is on and cancels a chooser whose tool went away.
        var syncCaptureSurface: @MainActor () -> Void
        /// The same call on the way out: a no-op on a Mac where no start ever reached the chooser.
        var resyncCaptureSurface: @MainActor () -> Void
        var syncOCR: @MainActor () -> Void
        /// Cancels a recognition in flight and closes a QR result still on screen.
        var suspendOCR: @MainActor () -> Void
        /// Arms the preview shortcut and the camera safety.
        var startCamera: @MainActor () -> Void
        /// Closes the preview (releasing the capture session) and disarms the camera safety. Idempotent.
        var stopCamera: @MainActor () -> Void
        /// The quit hook (live: one observer; fake: records).
        var watchQuit: @MainActor () -> Void
        var unwatchQuit: @MainActor () -> Void

        /// Services are only built once a start reached them: a Mac where the feature stays off builds nothing.
        @MainActor private static var captureTouched = false
        @MainActor private static var cameraTouched = false

        static let live: Runtime = {
            let watcher = LiveQuitWatcher()
            return Runtime(
                syncCaptureSurface: { captureTouched = true; ScreenCaptureService.shared.syncWithPreferences() },
                resyncCaptureSurface: { if captureTouched { ScreenCaptureService.shared.syncWithPreferences() } },
                syncOCR: { captureTouched = true; ScreenTextService.shared.syncWithPreferences() },
                suspendOCR: {
                    if captureTouched { ScreenTextService.shared.suspend() }
                    QRResultController.shared.close()
                },
                startCamera: {
                    cameraTouched = true
                    CameraSafety.live.attach(to: CameraPreviewService.shared)
                    CameraPreviewService.shared.syncWithPreferences()
                },
                stopCamera: {
                    guard cameraTouched else { return }
                    CameraPreviewService.shared.suspend()  // hide(): releases the session, withdraws the indicator
                    CameraSafety.live.detach(from: CameraPreviewService.shared)
                },
                watchQuit: { watcher.install() },
                unwatchQuit: { watcher.remove() })
        }()
    }

    /// Upstream feature id -> the Settings page that carries its body (`SettingsPageCatalog` ids, rows 10, 16, 17).
    static let pageIDs: [String: String] = [
        "cameraPreview": "camera", "screenOCR": "ocr", "colorPicker": "colorpicker",
    ]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(
            "screenOCR",
            page: PortFeaturePage(pageID: "ocr") { AnyView(ScreenTextPage()) },
            start: {
                runtime.syncOCR()
                runtime.syncCaptureSurface()
            },
            stop: {
                runtime.suspendOCR()
                runtime.resyncCaptureSurface()
            })
        binding.bind(
            "colorPicker",
            page: PortFeaturePage(pageID: "colorpicker") { AnyView(ColorPickerPage()) },
            start: { runtime.syncCaptureSurface() },
            stop: { runtime.resyncCaptureSurface() })
        binding.bind(
            "cameraPreview",
            page: PortFeaturePage(pageID: "camera") { AnyView(CameraPreviewPage()) },
            start: {
                runtime.startCamera()
                runtime.watchQuit()
            },
            stop: {
                runtime.unwatchQuit()
                runtime.stopCamera()
            })
    }
}

/// The quit hook: leaving the app releases the camera before the process ends.
private final class LiveQuitWatcher: @unchecked Sendable {
    private var token: NSObjectProtocol?

    @MainActor func install() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CameraPreviewService.shared.shutdownForQuit() }
        }
    }

    @MainActor func remove() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}

// MARK: - Permission click hook

/// The permissions the capture pages can ask for.
public enum PortCapturePermission: Sendable {
    case screenRecording
}

public enum PortCaptureTools {
    /// The "Autoriser" click of the OCR page. The app delegate plugs `UserPermissionRequest.request` in (ShellKit asks
    /// once so macOS lists the app, then opens the pane). Unset (tests, a build without it): the pane opens and nothing
    /// is asked. Only ever called from a click.
    @MainActor public static var requestPermission: (@MainActor (PortCapturePermission) -> Void)?
}

// MARK: - Camera safety

/// Where the camera indicator is posted. `AmbientCenter` in the app, a recorder in tests.
@MainActor
protocol CameraIndicatorPoster {
    func post(_ indicator: AmbientIndicator)
    func withdraw(id: String)
}

extension AmbientCenter: CameraIndicatorPoster {}

/// The camera must never stay on without the user seeing it. While a capture session exists (the service reports it
/// through `onSessionChange`), this shows an always-on indicator in the island and runs a 5 minute inactivity timer;
/// any interaction with the preview (`noteActivity`) restarts it, and when it fires the preview closes, which
/// releases the session. Clock and island are injected, so tests drive it with a fake clock and a recorder.
@MainActor
final class CameraSafety {
    /// How long a preview nobody touches stays open.
    nonisolated static let inactivityLimit: TimeInterval = 300
    static let indicatorID = "capture.camera"

    typealias Cancel = @MainActor () -> Void
    /// Runs the closure after the delay on the main actor; the returned closure cancels it.
    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Cancel

    /// The channel is `alert`, never `camera`: the `camera` channel is a Settings switch (off by default) for OTHER
    /// apps' cameras, and this one is Mac Island's own, so it cannot be switched off. Pinned (alert priority), green
    /// with its meaning also in the label (colour is never the only signal).
    static var indicator: AmbientIndicator {
        AmbientIndicator(
            id: indicatorID, channel: AmbientChannel.alert, symbol: "video.fill", status: .success, priority: .alert,
            label: "Caméra active : l’aperçu de Mac Island est ouvert")
    }

    private let poster: CameraIndicatorPoster
    private let schedule: Schedule
    private let closePreview: @MainActor () -> Void
    private let limit: TimeInterval
    private var cancelTimer: Cancel?
    private(set) var isSessionActive = false

    init(poster: CameraIndicatorPoster, schedule: @escaping Schedule, closePreview: @escaping @MainActor () -> Void,
         limit: TimeInterval = CameraSafety.inactivityLimit) {
        self.poster = poster
        self.schedule = schedule
        self.closePreview = closePreview
        self.limit = limit
    }

    /// A capture session now exists (true) or was released (false).
    func sessionChanged(active: Bool) {
        isSessionActive = active
        if active {
            poster.post(Self.indicator)
            arm()
        } else {
            cancelTimer?()
            cancelTimer = nil
            poster.withdraw(id: Self.indicatorID)
        }
    }

    /// The user touched the preview: the inactivity countdown starts over.
    func noteActivity() {
        guard isSessionActive else { return }
        arm()
    }

    /// Everything off, whatever the service says: the feature stopped or the app is quitting.
    func reset() {
        sessionChanged(active: false)
    }

    private func arm() {
        cancelTimer?()
        cancelTimer = schedule(limit) { [weak self] in self?.timedOut() }
    }

    private func timedOut() {
        cancelTimer = nil
        guard isSessionActive else { return }
        closePreview()
        // The service reports the release itself; this makes the indicator and the timer go even if it did not.
        sessionChanged(active: false)
    }

    // MARK: Live

    /// The app's one safety: the island's ambient center, the main queue, the shared preview service.
    static let live = CameraSafety(
        poster: AmbientCenter.shared,
        schedule: { delay, fire in
            let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        },
        closePreview: { CameraPreviewService.shared.hide() })

    /// Connects the service's two hooks. Idempotent.
    func attach(to service: CameraPreviewService) {
        service.onSessionChange = { [weak self] active in
            MainActor.assumeIsolated { self?.sessionChanged(active: active) }
        }
        service.onUserActivity = { [weak self] in
            MainActor.assumeIsolated { self?.noteActivity() }
        }
    }

    func detach(from service: CameraPreviewService) {
        service.onSessionChange = nil
        service.onUserActivity = nil
        reset()
    }
}

// MARK: - Pages (settings 10, 16 and 17)

/// The shortcut rows of one capture tool: the toggle, the recorder, whether the shortcut opens the capture menu.
/// (The tool picker and the recent captures belong to the screenshot page.)
private struct CaptureToolShortcutRows: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ScreenCaptureService.shared
    @AppStorage private var enabled: Bool
    @AppStorage private var showsCaptureMenu: Bool

    private let tool: ScreenCaptureTool
    private let keys: ScreenCaptureTool.DedicatedShortcut

    init(tool: ScreenCaptureTool) {
        self.tool = tool
        self.keys = tool.dedicatedShortcut
        _enabled = AppStorage(wrappedValue: false, keys.enabledKey)
        _showsCaptureMenu = AppStorage(wrappedValue: true, tool.showCaptureMenuOnShortcutKey)
    }

    var body: some View {
        Toggle(keys.role.title(l10n.s), isOn: $enabled)
            .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
        ShortcutPreferenceRow(role: keys.role, isEnabled: enabled) {
            service.syncWithPreferences()
        }
        Toggle(FeatureStrings.screenshot(l10n.language).showCaptureMenuOnShortcut, isOn: $showsCaptureMenu)
            .disabled(!enabled)
        if enabled, service.toolShortcutRegistrationFailures.contains(tool) {
            Text(l10n.s.shortcutUnavailable)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

/// A caption under a control.
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Page 16: Copier le texte à l'écran.
private struct ScreenTextPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(AppFeature.screenOCR.availabilityKey) private var featureOn = false
    @AppStorage(DefaultsKey.screenOCRRemoveLineBreaks) private var removesLineBreaks = false
    @AppStorage(DefaultsKey.screenOCRDetectQRCodes) private var detectsQRCodes = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: FeatureStrings.screenshot(l10n.language).screenCaptureTitle) {
                CaptureToolShortcutRows(tool: .text)
            }
            SettingsCard(title: l10n.s.ocrName) {
                Button {
                    ScreenTextService.shared.capture()
                } label: {
                    Label(l10n.s.ocrName, systemImage: "text.viewfinder")
                }
                .disabled(!featureOn || !permissions.screenRecording)
                Caption(l10n.s.ocrCaption)
                Toggle(l10n.s.ocrRemoveLineBreaksToggle, isOn: $removesLineBreaks)
                Caption(l10n.s.ocrRemoveLineBreaksCaption)
                Toggle(l10n.s.ocrQRToggle, isOn: $detectsQRCodes)
                Caption(l10n.s.ocrQRCaption)
                Caption("Un lien lu dans un code QR s’ouvre seulement quand vous cliquez sur « Ouvrir » ; son contenu s’affiche d’abord. Tout se lit sur votre Mac, rien n’est envoyé.")
                if !permissions.screenRecording {
                    ScreenRecordingNote()
                }
            }
        }
        .toggleStyle(.switch)
    }
}

/// OCR cannot capture without Screen Recording. The click asks through the hook the app plugs in (or opens the pane).
private struct ScreenRecordingNote: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 8) {
            Label("Enregistrement de l’écran : nécessaire pour lire le texte à l’écran.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Autoriser") {
                if let ask = PortCaptureTools.requestPermission {
                    ask(.screenRecording)
                } else {
                    Permissions.shared.openScreenRecordingSettings()
                }
            }
            .controlSize(.small)
        }
    }
}

/// Page 17: Pipette de couleur.
private struct ColorPickerPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(AppFeature.colorPicker.availabilityKey) private var featureOn = false
    @AppStorage(DefaultsKey.colorPickerFormat) private var format = "hex"
    @AppStorage(DefaultsKey.colorPickerBareHex) private var usesBareHex = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: FeatureStrings.screenshot(l10n.language).screenCaptureTitle) {
                CaptureToolShortcutRows(tool: .color)
            }
            SettingsCard(title: l10n.s.colorPickerName) {
                Button {
                    ColorSamplerService.shared.pick()
                } label: {
                    Label(l10n.s.colorPickerPickNow, systemImage: "eyedropper")
                }
                .disabled(!featureOn)
                Caption(l10n.s.colorPickerCaption)
                Picker(l10n.s.colorPickerFormatLabel, selection: $format) {
                    ForEach(ColorCopyFormat.allCases) { format in
                        Text(format.label).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                if format == ColorCopyFormat.hex.rawValue {
                    Toggle(l10n.s.colorPickerBareHexToggle, isOn: $usesBareHex)
                }
                if !permissions.screenRecording {
                    Caption("Sans l’enregistrement de l’écran, la pipette de macOS prend le relais : elle n’a besoin d’aucune autorisation.")
                }
            }
        }
        .toggleStyle(.switch)
    }
}

/// Page 10: Aperçu de la caméra.
private struct CameraPreviewPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(AppFeature.cameraPreview.availabilityKey) private var featureOn = false
    @AppStorage(DefaultsKey.cameraPreviewShortcutEnabled) private var shortcutEnabled = false

    private var strings: CameraPreviewFeatureStrings { FeatureStrings.cameraPreview(l10n.language) }

    var body: some View {
        SettingsCard(title: strings.pageTitle) {
            Button {
                CameraPreviewService.shared.show()
            } label: {
                Label(strings.openButton, systemImage: "web.camera")
            }
            .disabled(!featureOn)
            Caption(strings.panelCaption)
            if service.state == .running || service.state == .starting {
                HStack(spacing: 8) {
                    Label("Caméra active", systemImage: "video.fill")
                        .foregroundStyle(.green)
                    Spacer(minLength: 8)
                    Button("Arrêter") { CameraPreviewService.shared.hide() }
                        .controlSize(.small)
                }
            }
            Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                .onChange(of: shortcutEnabled) { _, _ in CameraPreviewService.shared.syncWithPreferences() }
            ShortcutPreferenceRow(role: .cameraPreview, isEnabled: shortcutEnabled) {
                CameraPreviewService.shared.syncWithPreferences()
            }
            if shortcutEnabled, service.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            cameraPermissionRow
            Caption("L’aperçu n’allume la caméra que tant qu’il est ouvert. Il se ferme avec Échap, un clic ailleurs, un changement d’app, la désactivation de la fonction ou la fermeture de Mac Island, et tout seul après 5 minutes sans action. Un point vert s’affiche dans l’île tant que la caméra est active. Rien n’est enregistré.")
        }
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private var cameraPermissionRow: some View {
        switch permissions.camera {
        case .granted:
            Label("\(strings.permName) : autorisée", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .undetermined:
            HStack(spacing: 8) {
                Label("\(strings.permName) : jamais demandée.", systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Spacer(minLength: 8)
                Button("Autoriser") { Permissions.shared.requestCamera() }  // a click: the one place the page asks
                    .controlSize(.small)
            }
        case .denied:
            HStack(spacing: 8) {
                Label("\(strings.permName) : refusée dans les Réglages Système.", systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Spacer(minLength: 8)
                Button(l10n.s.permissionOpenSettings) { Permissions.shared.openCameraSettings() }
                    .controlSize(.small)
            }
        case .unknown:
            EmptyView()
        }
    }
}
