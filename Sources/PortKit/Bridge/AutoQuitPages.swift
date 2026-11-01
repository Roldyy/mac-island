// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W3D (auto-quit and Spaces). The lane owns this file.

import AppKit
import SwiftUI

// The two Settings pages of the lane (our page ids `quitonclose` = 31 and `spaces` = 34). Each is drawn from
// the ported cards and rows, without the Form, title and scroll view the upstream pages carry (Mac Island's
// page scaffold has its own), and shows its controls even while the registry holds the feature off, so the
// switch and the settings stay reachable. No control here prompts: a missing permission opens System Settings.

// MARK: - Page 31: Quitter à la fermeture

struct AutoQuitPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AutoQuitService.shared
    @ObservedObject private var idle = AutoQuitIdleMonitor.shared
    @AppStorage(DefaultsKey.autoQuitEnabled) private var enabled = false
    @AppStorage(AutoQuitIdleKeys.enabled) private var idleEnabled = false
    @AppStorage(AutoQuitIdleKeys.delayMinutes) private var delayMinutes = AutoQuitIdleKeys.defaultDelayMinutes
    @AppStorage(AutoQuitIdleKeys.dryRun) private var dryRun = true
    @State private var showingAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            lastWindowCard
            idleCard
            rulesCard
            exceptionsCard
            if (enabled || idleEnabled), !permissions.accessibility {
                SettingsCard(title: l10n.s.permissionRequired) { PermissionRow(kind: .accessibility) }
            }
        }
        .toggleStyle(.switch)
        .sheet(isPresented: $showingAppPicker) { appPickerSheet }
    }

    // MARK: Cards

    private var lastWindowCard: some View {
        SettingsCard {
            SettingsRow(symbol: AppFeature.autoQuit.symbolName, title: l10n.s.autoQuitEnable,
                        caption: l10n.s.autoQuitEnableCaption) {
                Toggle(l10n.s.autoQuitEnable, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, _ in AutoQuitService.shared.syncWithPreferences() }
            }
            if !PortShortcutOwnership.isRunning(.autoQuit) {
                Text("La fonction « Quitter à la fermeture » est coupée (interrupteur de la carte ci-dessus, interrupteur d’arrêt ou mode sans échec) : aucune app n’est quittée.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if enabled, service.isRunning {
                Label(l10n.s.autoQuitActiveNow, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var idleCard: some View {
        SettingsCard(title: "Apps restées sans fenêtre") {
            SettingsRow(symbol: "hourglass", title: "Quitter les apps inactives",
                        caption: "Une app sans aucune fenêtre depuis le délai choisi est annoncée, puis quittée après 60 s si vous ne la gardez pas.") {
                Toggle("Quitter les apps inactives", isOn: $idleEnabled)
                    .labelsHidden()
                    .onChange(of: idleEnabled) { _, _ in AutoQuitIdleMonitor.shared.sync() }
            }
            if idleEnabled {
                Divider()
                Stepper(value: $delayMinutes, in: 1...AutoQuitIdleKeys.maxDelayMinutes, step: 5) {
                    Text("Après \(delayMinutes) min sans fenêtre")
                }
                .accessibilityLabel("Délai d’inactivité en minutes")
                Toggle("Simulation seulement (ne rien quitter)", isOn: $dryRun)
                    .accessibilityLabel("Mode simulation")
                Text(dryRun
                     ? "Simulation : l’annonce s’affiche ici, mais aucune app n’est quittée. Désactivez-la pour que les apps annoncées soient vraiment quittées."
                     : "Les apps annoncées sont quittées quand le compte à rebours se termine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                pendingList
            }
        }
    }

    @ViewBuilder private var pendingList: some View {
        if idle.pending.isEmpty {
            Text("Aucune app à quitter pour le moment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(dryRun ? "Simulation, quitterait :" : "Va quitter :")
                        .font(.caption.weight(.semibold))
                    ForEach(idle.pending) { item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text("\(max(0, Int(item.deadline.timeIntervalSince(context.date).rounded(.up)))) s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Garder") {
                                if let id = item.bundleID {
                                    service.addException(id)
                                    idle.tick()
                                }
                            }
                            .accessibilityLabel("Garder \(item.name) ouverte")
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private var rulesCard: some View {
        SettingsCard(title: l10n.s.autoQuitHowTitle) {
            bullet("rectangle.badge.xmark", l10n.s.autoQuitStep1)
            bullet("bolt.fill", l10n.s.autoQuitStep2)
            Text(l10n.s.autoQuitPredictableNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("Jamais quittées : le Finder, Mac Island, les apps qui jouent du son, celles qui ont une fenêtre « Enregistrer » ou une alerte ouverte, et celles de la liste ci-dessous. L’app au premier plan n’est jamais quittée pour inactivité.",
                  systemImage: "shield.checkered")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(l10n.s.autoQuitOngoingWorkNote, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exceptionsCard: some View {
        SettingsCard(title: l10n.s.autoQuitExceptionsTitle) {
            if sortedExceptions.isEmpty {
                Text(l10n.s.autoQuitExceptionsEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedExceptions, id: \.self) { bundleID in
                    HStack(spacing: 9) {
                        Image(nsImage: InstalledApps.icon(for: bundleID))
                            .resizable().frame(width: 20, height: 20)
                        Text(InstalledApps.name(for: bundleID))
                        Spacer()
                        if service.isMandatoryException(bundleID) {
                            Image(systemName: "lock.fill").foregroundStyle(.tertiary)
                        } else {
                            Button {
                                service.removeException(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Retirer \(InstalledApps.name(for: bundleID)) de la liste")
                        }
                    }
                }
            }
            Button {
                showingAppPicker = true
            } label: {
                Label(l10n.s.autoQuitAddApp, systemImage: "plus")
            }
            Text(l10n.s.autoQuitExceptionsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: State

    private var sortedExceptions: [String] {
        AutoQuitSupport.visibleExceptions(service.exceptions) { InstalledApps.url(for: $0) != nil }
            .sorted {
                InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                    == .orderedAscending
            }
    }

    private var appPickerSheet: some View {
        let excluded = Set(service.exceptions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            service.addException(bundleID)
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: excluded)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 34: Garder les Espaces dans un ordre fixe

struct SpacesOrderPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.spacesOrderEnabled) private var spacesOrderEnabled = false
    /// The recovery note the hold writes while it holds the Dock setting; its presence is the "held" state.
    @AppStorage(DefaultsKey.spacesOrderRestore) private var heldMarker = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard {
                SettingsRow(symbol: AppFeature.spacesOrder.symbolName, title: l10n.s.spacesOrderName,
                            caption: l10n.s.spacesOrderCaption) {
                    Toggle(l10n.s.spacesOrderName, isOn: $spacesOrderEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: spacesOrderEnabled) { _, _ in
                            SpacesOrderHold.shared.syncWithPreferences()
                        }
                }
                if !PortShortcutOwnership.isRunning(.spacesOrder) {
                    Text("La fonction est coupée (interrupteur de la carte ci-dessus, interrupteur d’arrêt ou mode sans échec) : le réglage du Dock n’est pas touché.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if spacesOrderEnabled, !heldMarker.isEmpty {
                    Label("Ordre fixe appliqué", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            SettingsCard(title: "Ce que ça change") {
                Text("Mac Island coupe le réglage « Réorganiser automatiquement les Spaces d’après l’utilisation la plus récente » du Dock. Le Dock redémarre une fois quand vous activez ou désactivez cette option : l’écran clignote une seconde, vos fenêtres ne bougent pas.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Votre réglage d’origine est rétabli quand la fonction s’arrête (interrupteur, mode sans échec), quand vous quittez Mac Island, et au prochain lancement si l’app s’est arrêtée sans prévenir. Si vous le rallumez vous-même dans Réglages Système, Mac Island s’efface et ne le recoupe pas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
