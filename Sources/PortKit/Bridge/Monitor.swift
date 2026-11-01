// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W6A (samplers and alerts). The lane owns this file.

import AppKit
import SwiftUI

/// Binds the seven monitor families of the ported code through `PortFeatureBinding`, each OFF until the registry says
/// on (a migrated or user-chosen `shell.enabled.<id>`), none of them ever prompting:
///
/// `monitorCPU`, `monitorGPU`, `monitorMemory`, `monitorNetwork`, `monitorDisk`, `monitorPower` and
/// `connectedDevices`. Upstream's `SystemMonitor` is the one sampler (CPU, GPU, memory, network and per-app traffic
/// through `nettop`, disks, power, USB devices, SMC temperatures) and it is already on demand: it samples only while a
/// surface that needs a reading is open, a metric is pinned in the menu bar, or an alert is on, and its plan drops a
/// whole family the moment `AppFeature.monitorX.isAvailable` turns false. So a family has nothing of its own to start:
/// start and stop both re-sync the plan, the alerts and the menu bar items (`runtime.sync`).
///
/// What the lane brings, besides the switches:
/// - the Settings page `monitor` (the whole ported page: menu bar metrics, panel blocks, readings, alerts), under the
///   `monitor` feature card its catalog row carries (our island card keeps that id);
/// - the menu bar metrics (`MenuBarMetricsHost`, `Bridge/MenuBar.swift`), driven by the same sync;
/// - alerts: `MonitorAlertService` runs while an alert is on for an available family. It never asks for the
///   notification permission by itself (patch 1400): the Settings switches do, on the click.
///
/// Nothing is built until a start reached it: a Mac where every family stays off never touches `SystemMonitor`.
enum MonitorLane {
    static let pageID = "monitor"

    /// Upstream raw ids, in binding order (this is the order of the Features page).
    static let familyIDs = ["monitorCPU", "monitorGPU", "monitorMemory", "monitorNetwork", "monitorDisk", "monitorPower",
                            "connectedDevices"]

    /// What the lane does to the ported services. Tests pass a fake: the live one starts real sampling.
    struct Runtime {
        /// A family started: bring the sampling plan, the alerts and the menu bar items up to date.
        var start: @MainActor () -> Void
        /// A family stopped (its availability is already false): the same, so the plan drops it.
        var stop: @MainActor () -> Void

        static let live = Runtime(start: { MonitorLive.start() }, stop: { MonitorLive.stop() })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installPage()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        for id in familyIDs {
            binding.bind(id, start: runtime.start, stop: runtime.stop)
        }
    }

    private nonisolated(unsafe) static var didInstallPage = false

    /// The catalog row `monitor` already carries the feature card (our own `monitor` id): a plain page body.
    @MainActor static func installPage() {
        guard !didInstallPage else { return }
        didInstallPage = true
        PortBridge.register(pageID: pageID) { AnyView(MonitorPage()) }
    }
}

/// The live side of the runtime.
enum MonitorLive {
    /// True once a start reached the ported monitor: only then does a stop have anything to give back.
    @MainActor private(set) static var touched = false

    @MainActor static func start() {
        touched = true
        sync()
    }

    @MainActor static func stop() {
        guard touched else { return }
        sync()
    }

    @MainActor private static func sync() {
        SystemMonitor.shared.planDidChange()
        // No prompt from here: `askForNotifications` stays false, the Settings switches pass true.
        MonitorAlertService.shared.syncWithPreferences()
        let host = MenuBarMetricsHost.shared
        host.installLiveObservers()
        host.sync()
    }
}

/// Page 5: the ported Monitor page, in a frame of its own height (the page scrolls inside, the live menu bar preview
/// stays pinned above the choices that change it).
private struct MonitorPage: View {
    var body: some View {
        MonitorSettings()
            .frame(height: 680)
            .islandGlass()
    }
}
