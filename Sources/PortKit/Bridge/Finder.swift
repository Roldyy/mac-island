// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W7A (Finder and DMG). The lane owns this file.

import AppKit
import SwiftUI

// MARK: - Finder lane

/// Binds the ported Finder services, which REPLACE the key tap of our `Sources/Features/Finder` module: cut and paste
/// of files (⌘X, ⌘V, the floating panel, the progress bar of a move that leaves its volume) and the rename shortcut
/// (F2, or the key the person records, turned into Finder's own Rename).
///
/// REPLACE, decided with evidence (port plan 4, lane 7A):
/// - Our module has no feedback panel, no progress for a cross-volume move and no rename shortcut. The Settings rows
///   the reference page shows ("Afficher le panneau flottant", "Raccourci pour renommer") exist only in the ported code.
/// - Two taps on one key would move every file twice, so only one engine may run. The ported one does: the app delegate
///   no longer passes `FinderFeature.start` and `stop`, and the island tab (`Sources/Features/Finder`) defers to it
///   through `FinderFeature.engineStatus` (it shows the state, forwards its two switches, installs nothing).
/// - Both services keep their own option (`finderCutPasteEnabled`, `finderRenameEnabled`, `finderPasteImageAsFile`):
///   the keys our module already read and the migrator copies, so nothing is lost on the way over.
///
/// One registry feature, `finder` (`PortFeatureIDs`: `finderCutPaste` owns it, `finderRename` is folded into it). The
/// registry keeps OUR descriptor (title, switch, island tab, Accessibility and Automation status). Start and stop both
/// re-read the preferences of both services, so:
/// - the switch off, the kill switch, safe mode and quarantine remove both taps (each service reads `isAvailable`, which
///   the binding answers with the registry's verdict) and forget the cut items;
/// - nothing here ever prompts. A key press with the Finder Automation grant missing does nothing and the key goes
///   through (patch 1501); the prompt comes from the click on "Autoriser" (`UserPermissionRequest.requestAutomation`).
enum FinderLane {
    /// What the lane does to the upstream services. The registry tests swap it for a recorder.
    struct Runtime {
        /// Re-reads the preferences of cut and paste and of the rename shortcut.
        var sync: @MainActor () -> Void
        /// Same re-read after the binding denied the feature (the services then remove their taps).
        var stop: @MainActor () -> Void

        @MainActor private static var touched = false

        static let live = Runtime(
            sync: { touched = true; PortFinder.syncPreferences() },
            // A stop that follows no start builds nothing.
            stop: { if touched { PortFinder.syncPreferences() } })
    }

    static let cutPastePageID = "cutpaste"
    static let renamePageID = "renameshortcut"

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        DiskImageLane.bind(into: binding)
        installPages()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bindReplacing("finderCutPaste", start: { runtime.sync() }, stop: { runtime.stop() })
    }

    private static var didInstallPages = false

    /// Both catalog rows (`cutpaste`, `renameshortcut`) carry the Finder card; the bodies are the two halves of the
    /// ported page (`CutPasteSettings(parts:)`, patch 1500).
    @MainActor private static func installPages() {
        guard !didInstallPages else { return }
        didInstallPages = true
        PortBridge.register(pageID: cutPastePageID) {
            AnyView(CutPasteSettings(parts: [.cutPaste]).defaultAppStorage(PortHost.defaults))
        }
        PortBridge.register(pageID: renamePageID) {
            AnyView(CutPasteSettings(parts: [.rename]).defaultAppStorage(PortHost.defaults))
        }
    }
}

/// What the island's Finder tab (`Sources/Features/Finder`) reads from, and forwards to, the ported engine.
/// The app delegate plugs it into `FinderFeature.engineStatus`, `engineSync` and `engineCancelCut`.
public enum PortFinder {
    /// True while the cut and paste tap is installed.
    @MainActor public static var isRunning: Bool { FinderCutPaste.shared.isRunning }

    /// How many items ⌘X holds for a move.
    @MainActor public static var cutCount: Int { FinderCutPaste.shared.marked.count }

    /// Applies the stored preferences of both services (idempotent; each removes its tap when it is not wanted).
    @MainActor public static func syncPreferences() {
        FinderCutPaste.shared.syncWithPreferences()
        FinderRenameService.shared.syncWithPreferences()
    }

    /// Forgets the cut items without moving anything, then puts the tap back as the preferences say.
    @MainActor public static func cancelCut() {
        FinderCutPaste.shared.suspend()
        FinderCutPaste.shared.syncWithPreferences()
    }
}

// MARK: - Disk image installer lane

/// Binds the ported disk image installer: while a disk image is mounted by the person, it offers to install the one
/// app inside it into Applications (after a signature check), eject the image and put the download in the Trash.
///
/// A new feature (`diskImageInstaller`), OFF until the person switches it on in the Features page: it watches mount
/// notifications only while on, and acts only on an image that holds exactly one app and only after the person pressed
/// "Installer" in its own alert (patch-free: the ported service already confirms, verifies with `codesign` and
/// `spctl`, never overwrites an installed app and moves the download to the Trash, never deletes it). Its three
/// options (Trash the download, reveal the app, install in the home Applications folder) live in that alert, where
/// the choice is made, as upstream has them.
enum DiskImageLane {
    struct Runtime {
        var sync: @MainActor () -> Void
        var stop: @MainActor () -> Void

        @MainActor private static var touched = false

        static let live = Runtime(
            sync: { touched = true; DiskImageInstallerService.shared.syncWithPreferences() },
            stop: { if touched { DiskImageInstallerService.shared.syncWithPreferences() } })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind("diskImageInstaller", start: { runtime.sync() }, stop: { runtime.stop() })
    }
}
