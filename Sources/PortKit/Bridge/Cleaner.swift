// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W7B (cleaner). The lane owns this file.

import AppKit
import SwiftUI

// MARK: - Cleaner lane

/// Binds the ported cleaner: junk that piles up (caches, logs, developer build leftovers, leftovers of uninstalled
/// apps, orphaned startup items, old device backups, forgotten screenshots), reviewed path by path before anything
/// moves, and the WhatsApp downloads organizer that shares its page and its switch.
///
/// A new feature (`cleaner`), OFF until the person switches it on: the switch governs the two background services (the
/// schedule and the WhatsApp organizer); the scan itself only ever starts from its button. What the lane guarantees, and
/// where each guarantee lives (the tests read these sources, `CleanerSafetyTests`):
/// - PREVIEW FIRST. Nothing runs at launch or at a switch: a scan starts from the "Analyser" button, lists every path with
///   its size, and only what the person leaves checked is cleaned. The uncertain finds start unchecked. The one
///   unattended path is the schedule, which is off until the person picks a frequency and cleans only the groups the scan
///   pre-checks as safe.
/// - TRASH ONLY. Every removal is a move to the Trash (`FileManager.trashItem`), recoverable there. The Trash itself is
///   no longer offered and `emptyTrash` refuses (patch 1502), so nothing in this tool deletes in place.
/// - NO HIDDEN PROMPT. A root-owned item is left where it is instead of being handed to Finder (an administrator
///   password, patch 1502), and the Finder helper that remains reads the Automation state instead of asking for it.
/// - The notification a finished scheduled run posts goes through `Notifier.post`, which drops the note when macOS
///   notifications are not allowed; the system question itself is asked by the page's own switch, on a click.
enum CleanerLane {
    /// What the lane does to the upstream services. The registry tests swap it for a recorder.
    struct Runtime {
        /// Re-reads the preferences of the schedule and of the WhatsApp services (each stops itself while the feature
        /// is not available, which is how a stop works too).
        var sync: @MainActor () -> Void
        var stop: @MainActor () -> Void

        @MainActor private static var touched = false

        static let live = Runtime(
            sync: { touched = true; syncServices() },
            stop: { if touched { syncServices() } })

        @MainActor private static func syncServices() {
            CleanerScheduler.shared.syncWithPreferences()
            WhatsAppDownloadScheduler.shared.syncWithPreferences()
            WhatsAppDownloadOrganizer.shared.syncWithPreferences()
        }
    }

    static let pageID = "cleaner"

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installPages()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind("cleaner", start: { runtime.sync() }, stop: { runtime.stop() })
    }

    private static var didInstallPages = false

    /// The catalog row `cleaner` carries the feature card (`featureID: "cleaner"`); the body is the ported page: the
    /// scan, the review, the schedule, the screenshot age and the WhatsApp tool.
    @MainActor private static func installPages() {
        guard !didInstallPages else { return }
        didInstallPages = true
        PortBridge.register(pageID: pageID) { AnyView(CleanerPageBody().defaultAppStorage(PortHost.defaults)) }
    }
}

/// The upstream page lays itself out as a full-height detail pane (a `GeometryReader` over its own scroll views).
/// Inside a Settings page that already scrolls, it gets a fixed height on a frosted card instead.
private struct CleanerPageBody: View {
    var body: some View {
        CleanerSettings()
            .frame(height: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
