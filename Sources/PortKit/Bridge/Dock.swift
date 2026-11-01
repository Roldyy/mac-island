// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W3C (dock). The lane owns this file.

import AppKit
import IslandKit
import SwiftUI

// MARK: - Lane

/// Binds the two ported Dock features as ONE registry feature, `dock` (`PortFeatureIDs`: `dockPreview` owns the id,
/// `dockClick` is folded into it). The ported services REPLACE our old `Sources/Features/Dock` module: the registry
/// keeps OUR descriptor (title, switch, island tab `dock`, Home tile, migrated `shell.enabled.dock`), so nothing is
/// added to the feature list and the shared settings keys (`dockPreviewEnabled`, `dockClickMinimize`,
/// `dockClickHide`, `dockClickCycleWindows`) keep their meaning.
///
/// What the registry does, all through `Runtime` so tests never touch an event tap or the Dock:
/// - start (`dock` switched on, Accessibility seen by the monitor, or granted later: the registry restarts the
///   feature on a grant) = move the old preview delay across once, then each service re-reads its own options.
///   Both services stay idle unless an option is on: `dockPreviewEnabled` and the three `dockClick*` options are
///   off until the user chooses them. Dock Preview needs Accessibility only; Screen Recording adds the
///   thumbnails (the ported capture checks it before any capture), without it the cards show the app icon. The
///   click service needs Accessibility.
/// - stop (switch off, kill switch, safe mode, quarantine, Accessibility revoked) = Dock Preview's session ends
///   (which hands a held Dock auto-hide back), its event tap and timers go, then the click tap goes.
///
/// Safety nets, in the order they act: the session end on every stop; the `willTerminate` hook below; the journal
/// `dockPreviewRestoreAutohide` (written BEFORE the Dock preference is touched by the optional "keep the Dock
/// visible" hold) and `recoverAtLaunch` for a run that died with the Dock held open. The hold is off by default.
/// Nothing here prompts: permissions are read, never requested, and the clicks on "Autoriser" go through
/// `UserPermissionRequest` (Settings page card) or `PortDock.requestPermission` (island tab).
enum DockLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        /// The delay of our retired module, once, into the ported key.
        var migrateLegacySettings: @MainActor () -> Void
        var syncClick: @MainActor () -> Void
        var syncPreview: @MainActor () -> Void
        /// Removes the click tap whatever the preferences say.
        var stopClick: @MainActor () -> Void
        /// Ends the hover session (and the Dock hold), removes the mouse tap, the timers and the pinned panels.
        var stopPreview: @MainActor () -> Void
        /// Gives a Dock auto-hide the journal says is owed back, whatever else happened.
        var restoreAutohide: @MainActor () -> Void
        /// The quit hook (live: one observer; fake: records).
        var watchApp: @MainActor () -> Void
        var unwatchApp: @MainActor () -> Void

        /// Services are only built once a start reached them: a Mac where the feature stays off builds nothing.
        @MainActor private static var clickTouched = false
        @MainActor private static var previewTouched = false

        static let live: Runtime = {
            let watcher = LiveQuitWatcher()
            return Runtime(
                migrateLegacySettings: { DockLegacySettings.migrateDelay(in: PortHost.defaults) },
                syncClick: { clickTouched = true; DockClickService.shared.syncWithPreferences() },
                syncPreview: { previewTouched = true; DockPreviewService.shared.syncWithPreferences() },
                stopClick: { if clickTouched { DockClickService.shared.suspend() } },
                stopPreview: { if previewTouched { DockPreviewService.shared.stop() } },
                restoreAutohide: { DockLane.recoverAtLaunch(defaults: PortHost.defaults) },
                watchApp: { watcher.install() },
                unwatchApp: { watcher.remove() })
        }()
    }

    /// Upstream feature id -> our Settings page id (`SettingsPageCatalog`, rows 29 and 30). Both catalog rows carry
    /// the `dock` feature card, so the bodies are plain page bodies (`PortBridge.register`).
    static let pageIDs: [String: String] = ["dockPreview": "dockpreview", "dockClick": "dockclicks"]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installPages()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bindReplacing(
            "dockPreview",
            start: {
                runtime.migrateLegacySettings()
                runtime.syncClick()
                runtime.syncPreview()
                runtime.watchApp()
            },
            stop: {
                runtime.unwatchApp()
                runtime.stopPreview()  // the session first: it hands a held Dock auto-hide back
                runtime.stopClick()
                runtime.restoreAutohide()
            })
    }

    private static var didInstallPages = false

    @MainActor private static func installPages() {
        guard !didInstallPages else { return }
        didInstallPages = true
        PortBridge.register(pageID: "dockpreview") { AnyView(DockPreviewPage().defaultAppStorage(PortHost.defaults)) }
        PortBridge.register(pageID: "dockclicks") { AnyView(DockClicksPage().defaultAppStorage(PortHost.defaults)) }
    }

    /// Everything the Dock features must give back before the process ends. Synchronous on purpose.
    @MainActor static func quit(runtime: Runtime) {
        runtime.stopPreview()
        runtime.stopClick()
        runtime.restoreAutohide()
    }

    /// A Dock auto-hide the journal says is owed (`dockPreviewRestoreAutohide`: set before the hold changes the Dock
    /// preference, removed once the preference is back). Entered only when that marker is set, so a Mac where the
    /// hold never ran makes no CoreDock call. Called from `PortBridge.recoverAtLaunch` and from every stop. When
    /// the write fails the marker stays and the next launch tries again. Returns true when nothing is owed.
    @MainActor @discardableResult
    static func recoverAtLaunch(defaults: UserDefaults,
                                makeHold: (UserDefaults) -> DockAutohideHold = { DockAutohideHold(defaults: $0) }) -> Bool {
        guard defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide) else { return true }
        makeHold(defaults).end()  // the initializer already tried once; `end` is idempotent
        return !defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide)
    }
}

/// The delay of our retired Dock module (`dockPreviewDelayMilliseconds`, 100 to 2000 ms) becomes the ported
/// `dockPreviewOpenDelay` (200 to 900 ms) once, clamped; the old key goes away. Nothing else of the old module
/// needs moving: its four other keys are the keys the ported services read.
enum DockLegacySettings {
    static let oldDelayKey = "dockPreviewDelayMilliseconds"

    @discardableResult
    static func migrateDelay(in defaults: UserDefaults) -> Int? {
        guard let old = defaults.object(forKey: oldDelayKey) as? NSNumber else { return nil }
        let delay = DockPreviewSupport.sanitizedOpenDelay(milliseconds: old.intValue)
        defaults.set(delay, forKey: DefaultsKey.dockPreviewOpenDelay)
        defaults.removeObject(forKey: oldDelayKey)
        return delay
    }
}

/// The quit hook: leaving the app hands a held Dock back and removes both taps before the process ends.
private final class LiveQuitWatcher: @unchecked Sendable {
    private var token: NSObjectProtocol?

    @MainActor func install() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DockLane.quit(runtime: .live) }
        }
    }

    @MainActor func remove() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}

// MARK: - Island tab

/// The permissions the Dock tab can ask for.
public enum PortDockPermission: Sendable {
    case accessibility, screenRecording
}

/// The island's "Dock" tab (id `dock`, kept): the ported Dock Preview and Dock click cards, hosted with the island
/// presentation, under a permission notice.
public enum PortDock {
    /// The "Autoriser" click of the tab. The app delegate plugs `UserPermissionRequest.request` in (ShellKit asks
    /// once so macOS lists the app, then opens the pane). Unset (tests, a build without it): the pane opens and
    /// nothing is asked. Only ever called from a click.
    @MainActor public static var requestPermission: (@MainActor (PortDockPermission) -> Void)?

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "dock", title: "Dock", systemImage: "dock.rectangle") {
            AnyView(DockIslandTab())
        }
    }
}

private struct DockIslandTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                DockPermissionNotice()
                DockSettings(parts: [.preview, .clicks])
            }
            .padding(10)
        }
        .environment(\.notchPresentation, true)
        .environment(\.colorScheme, .dark)
        .defaultAppStorage(PortHost.defaults)
    }
}

/// What is missing and the click that asks. Reads the permission state only.
private struct DockPermissionNotice: View {
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !permissions.accessibility {
                row("Accessibilité : nécessaire pour lire le Dock et les fenêtres des apps.", .accessibility)
            }
            if !permissions.screenRecording {
                row("Enregistrement de l’écran : facultatif, pour les vignettes des fenêtres.", .screenRecording)
            }
        }
    }

    private func row(_ text: String, _ permission: PortDockPermission) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Autoriser") { request(permission) }
                .controlSize(.small)
        }
    }

    private func request(_ permission: PortDockPermission) {
        if let ask = PortDock.requestPermission {
            ask(permission)
        } else {
            switch permission {
            case .accessibility: Permissions.shared.openAccessibilitySettings()
            case .screenRecording: Permissions.shared.openScreenRecordingSettings()
            }
        }
    }
}

// MARK: - Pages (settings 29 and 30)

/// Page 29: the Dock Preview card and the window previews it shares with the switcher.
private struct DockPreviewPage: View {
    var body: some View { DockSettings(parts: [.preview, .previewWindows]) }
}

/// Page 30: what a click on a Dock icon does.
private struct DockClicksPage: View {
    var body: some View { DockSettings(parts: [.clicks]) }
}
