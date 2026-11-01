// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W5A (clipboard). The lane owns this file.

import Foundation

/// What the ported clipboard code is allowed to do while OUR module (`Sources/Features/Clipboard`) is the history.
///
/// Decision of lane W5A (the evidence is in `ClipboardLane` below and in `ClipboardLaneTests`): the history store
/// stays ours. The ported `ClipboardHistoryService` is therefore a bystander: it must never record, write
/// `ClipboardHistory.json`, or sweep `ClipboardImages` (its sweep deletes every PNG its own entry list does not
/// name, in the very folder our store uses). Patch 1100 puts `portedStoreOwnsHistory` in front of each of those.
enum PortClipboard {
    /// False: our module is the one store and the one recorder. Only a later change that replaces our module with
    /// the ported service (its data migration, its tab, the app delegate's starter) may flip it, in the same change.
    nonisolated(unsafe) static var portedStoreOwnsHistory = false

    /// Posted by the registry's stopper for `clipboard`. `ClipboardFeature.stopRequested` is the same string:
    /// PortKit cannot import that target (and it cannot import PortKit), so a notification joins them.
    static let stopNotification = Notification.Name("be.roldy.macisland.clipboard.stop")
}

/// The clipboard lane: what it binds, and what it deliberately does not.
///
/// REPLACE or KEEP, decided with evidence (port plan 4, lane 5A; tasks `Lane W5-A`):
///
/// KEEP our store. The ported `ClipboardHistoryService` reads the same file name in the same folder, but:
/// 1. It does not read what our store writes. Ours writes `pinned: Bool`; the ported `ClipboardHistoryEntry` reads
///    `pinnedAt: Date?`, so every pin would silently become a plain entry. Its `id` is a `UUID`, ours any string.
/// 2. Its decode is all or nothing (`JSONDecoder().decode([ClipboardHistoryEntry].self)`): one entry it cannot read
///    and the whole history loads empty, then the next copy overwrites the file. Ours is entry by entry and now keeps
///    the original file (`ClipboardHistory.before-repair.json`) before it repairs anything.
/// 3. It refuses only `ConcealedType`; ours also refuses transient, auto-generated and the two legacy markers.
/// 4. Taking over needs three edits outside this lane's surface: `Package.swift` (the `ClipboardFeature` target would
///    import PortKit to keep the island tab), the app delegate's `"clipboard"` starter (it wins over the bound one),
///    and the declarative live rows of pages 49 and 50 in ShellKit (`SettingsLive`).
/// Each of 1 to 3 can be fixed by a patch; 4 cannot be done from here without leaving the surface. See the report.
///
/// What the lane does:
/// - `adopt`s the `clipboardHistory` stopper under OUR registry id `clipboard`. The app delegate passes our starter
///   (`ClipboardFeature.start()`) and it wins over the bound one; the stopper had no owner at all, so the kill switch,
///   the switch itself, safe mode and quarantine never stopped the recorder. The stopper now posts
///   `PortClipboard.stopNotification`, which a started `ClipboardModel` turns into `stop()`.
/// - Keeps `ported.starters["clipboard"]` a no-op ON PURPOSE: the app delegate's starter is the real one. Removing that
///   starter without wiring a real one here would silence the history; `ClipboardLaneTests` reads the delegate and
///   fails when the line goes.
/// - Does NOT bind `pastePlain` (our module owns the plain-paste hotkey, and two owners of one shortcut is the bug the
///   Features/Clipboard sequencer exists to prevent) nor `clipboardHistory` as a new feature. `urlCleaner` stays
///   bound by the foundation lane; it already leaves concealed and transient copies alone.
/// - Because the bound `clipboard` id is "not started" for the ported side, `AppFeature.clipboardHistory.isAvailable`
///   answers false there: the ported services that gate on it (history, auto-clear) stay down by themselves, and
///   patch 1100 covers the ones that do not.
enum ClipboardLane {
    /// What the lane does to the outside. Tests swap it for a recorder.
    struct Runtime {
        /// Tells our module to stop monitoring (live: the notification below).
        var stopModule: @MainActor () -> Void

        static let live = Runtime(stopModule: {
            NotificationCenter.default.post(name: PortClipboard.stopNotification, object: nil)
        })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.adopt(.clipboardHistory, start: {}, stop: { runtime.stopModule() })
    }
}
