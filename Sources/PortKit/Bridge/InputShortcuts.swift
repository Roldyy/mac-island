// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W1D (shortcuts, permissions, cleaning mode). The lane owns this file.

import IslandKit
import SwiftUI

// MARK: - Who owns which shortcut

/// One owner per shortcut role, and the two questions every ported shortcut surface asks before it touches a
/// feature.
///
/// - A feature is BOUND when a lane bound it through `PortFeatureBinding`: the registry decides whether it runs
///   (`PortHost.availability`). A feature nobody bound has no running service; the ported shortcut surfaces
///   (recorder, central page, `ShortcutCapture`) never start one: `FeatureRuntime.sync` would, from the stored
///   switch alone.
/// - Keep Awake's global shortcut is owned by Mac Island's own `KeepAwakeShortcutService` (Carbon, ⌃⌥⌘K by
///   default, `keepAwakeShortcutEnabled` and `keepAwakeShortcut`). The upstream `HotkeyManager` registers the
///   same key and stays idle (`upstreamKeepAwakeHotkeyAllowed` false) until the Energy lane retires one of the
///   two. The shortcuts of Clipboard, Shelf and Command bar likewise stay on our own pages until their lanes.
enum PortShortcutOwnership {
    /// False: only `KeepAwakeShortcutService` registers the Keep Awake key. Tests flip it.
    nonisolated(unsafe) static var upstreamKeepAwakeHotkeyAllowed = false

    /// A lane bound this feature (running or not).
    static func isBound(_ feature: AppFeature) -> Bool {
        PortHost.availability?(feature.registryID) != nil
    }

    /// A lane bound this feature and the registry lets it run right now.
    static func isRunning(_ feature: AppFeature) -> Bool {
        PortHost.availability?(feature.registryID) == true
    }

    /// The Keep Awake shortcut as Mac Island's page shows it: nil when the person switched it off.
    static func keepAwakeDisplay(in defaults: UserDefaults) -> String? {
        guard (defaults.object(forKey: "keepAwakeShortcutEnabled") as? Bool) ?? true else { return nil }
        let shortcut = defaults.string(forKey: DefaultsKey.keepAwakeShortcut).flatMap { GlobalShortcut(storageValue: $0) }
        return (shortcut ?? .keepAwakeDefault).displayString
    }
}

// MARK: - Cleaning mode, as the host sees it

/// The one cleaning mode of Mac Island: the ported `CleaningModeManager`, bound to the registry. The Home
/// "Nettoyage" button, the quick panel, the command bar and Settings all end up here.
public enum PortCleaningMode {
    public enum StartResult: Equatable, Sendable {
        case started, alreadyRunning
        /// The registry holds the feature down: switch off, kill switch, safe mode, quarantine.
        case featureOff
        case needsAccessibility
        /// The system refused the tap: nothing was swallowed.
        case refused
    }

    /// Swapped by tests; the app always uses the shared manager.
    @MainActor static var manager: CleaningModeManager = .shared

    private static let activityID = "cleaningMode.countdown"
    private static let source = "cleaningMode"

    @MainActor public static var isRunning: Bool { manager.isActive }

    /// Starts the lock when the registry allows it and Accessibility is granted. Never a system prompt, and no
    /// alert either: the caller says what is missing (the Home button puts a line in the closed island).
    @MainActor @discardableResult
    public static func start() -> StartResult {
        switch manager.activate(guideWhenMissing: false) {
        case .started: .started
        case .alreadyRunning: .alreadyRunning
        case .featureOff: .featureOff
        case .needsAccessibility: .needsAccessibility
        case .refused: .refused
        }
    }

    /// Ends cleaning now (app quit, the Home button pressed again). Idempotent.
    @MainActor public static func stop() { manager.stop(.quit) }

    /// The countdown lives in the closed island, like before the port. Wired once, when the lane binds.
    @MainActor static func wireIsland(_ manager: CleaningModeManager) {
        manager.onTick = { remaining in
            MainActor.assumeIsolated {
                ActivityCenter.shared.post(IslandActivity(
                    id: activityID, source: source, priority: .alert,
                    leading: CompactItem(symbol: "sparkles", text: "Nettoyage : \(remaining) s", status: .warning)))
            }
        }
        manager.onEnd = { reason in
            MainActor.assumeIsolated {
                ActivityCenter.shared.withdraw(id: activityID)
                guard reason != .quit && reason != .stopped else { return }
                ActivityCenter.shared.post(IslandActivity(
                    id: activityID, source: source, priority: .alert,
                    leading: CompactItem(symbol: "checkmark.circle.fill", text: "Nettoyage terminé", status: .success)),
                    expiresAfter: .seconds(3))
            }
        }
    }
}

// MARK: - The lane

/// Binds this lane's ported features. Called once at launch by `PortLanes`, before the registry exists.
///
/// - `cleaningMode`: start = nothing (cleaning begins only when the person asks; the registry's switch is the
///   permission to ask); stop = end the lock now, which is what the switch, the kill switch and safe mode call.
/// - Page 62 (Raccourcis clavier) is the ported central editor; it belongs to no single feature, so it is
///   registered as a plain page body.
enum InputShortcutsLane {
    @MainActor static func bind(into binding: PortFeatureBinding) {
        PortCleaningMode.wireIsland(PortCleaningMode.manager)
        binding.bind(
            .cleaningMode,
            page: PortFeaturePage(pageID: "cleaning") { AnyView(CleaningModePage()) },
            start: {},
            stop: { PortCleaningMode.manager.stop(.stopped) })
        PortBridge.register(pageID: "shortcuts") {
            AnyView(ShortcutsPage().defaultAppStorage(PortHost.defaults))
        }
    }
}

// MARK: - Page 13: Mode nettoyage

/// The cleaning section of the ported "Quick tools" page (start button, caption, keep-screen-visible), alone,
/// plus the guarantees in plain French. The switch and the status come from the card the page opens with.
struct CleaningModePage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var manager = CleaningModeManager.shared
    @AppStorage(DefaultsKey.cleaningModeKeepScreenVisible) private var keepScreenVisible = false

    var body: some View {
        Form {
            Section {
                Button {
                    CleaningModeManager.shared.activate()
                } label: {
                    Label(l10n.s.cleaningStartNow, systemImage: "bubbles.and.sparkles")
                }
                .disabled(manager.isActive)
                Text(l10n.s.cleaningPanelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n.s.cleaningKeepScreenVisibleToggle, isOn: $keepScreenVisible)
                Text(l10n.s.cleaningKeepScreenVisibleCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(l10n.s.cleaningMenuItem)
            }
            Section {
                Text("Le verrouillage s’arrête tout seul au bout de 60 secondes. Vous pouvez aussi maintenir Échap 3 secondes, appuyer 5 fois sur Échap ou cliquer sur Déverrouiller. Il s’arrête aussi si macOS coupe la capture, si l’autorisation Accessibilité disparaît ou si l’app se ferme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sécurité")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Page 62: Raccourcis clavier

/// The ported central editor, preceded by the shortcut Mac Island's own module owns.
struct ShortcutsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("keepAwakeShortcutEnabled") private var keepAwakeShortcutEnabled = true
    @AppStorage(DefaultsKey.keepAwakeShortcut) private var keepAwakeShortcut = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section {
                    HStack {
                        Label("Garder éveillé", systemImage: "cup.and.saucer")
                        Spacer()
                        Text(PortShortcutOwnership.keepAwakeDisplay(in: PortHost.defaults) ?? "Désactivé")
                            .foregroundStyle(.secondary)
                    }
                    Text("Ce raccourci se règle dans Général, sous « Raccourci global ». Les raccourcis de la barre de commande, du presse-papiers et de l’étagère se règlent sur leur propre page.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Raccourcis de Mac Island")
                }
            }
            .formStyle(.grouped)
            // Re-read when the General page changes the keys.
            .id("\(keepAwakeShortcutEnabled)-\(keepAwakeShortcut)")
            ShortcutsSettings()
        }
    }
}
