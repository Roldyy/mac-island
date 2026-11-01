// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W6D (kill and ports). The lane owns this file.

import AppKit
import SwiftUI

/// Binds the two ported features of lane W6-D through `PortFeatureBinding`, each OFF until the registry says on, and
/// neither of them ever prompts for a system permission:
///
/// - `killProcess` (Settings page `forcequit`, "Forcer à quitter"): the live list of processes with kill, force-kill,
///   kill-all, kill-tree and restart. The list is read with `ps` only while the page is open; a kill is one of the
///   person's clicks behind a confirmation, goes to the process by pid AND start time (a reused pid is never hit), and
///   skips protected processes (the system's, and Mac Island itself: patch 0010). A process the person does not own
///   needs the administrator password: that dialog is the system's, opened by that click and never by a start.
/// - `portManager` (page `ports`, "Gestionnaire de ports"): the listening TCP ports (`lsof`, read-only) and who holds
///   them. Its kill buttons exist only while `killProcess` is on (they go through `KillProcessService`), so turning
///   the kill switch of `killProcess` off leaves a read-only list.
///
/// Neither service runs anything at rest: no timer, no observer, no process. Their only clocks belong to the page
/// views (a refresh while the window is active). A start therefore has nothing to arm, and a stop nothing to give
/// back: the registry's verdict is what `AppFeature.killProcess.isAvailable` answers, which is what refuses a kill.
enum KillPortsLane {
    static let pageIDs: [String: String] = ["killProcess": "forcequit", "portManager": "ports"]

    /// What the lane does to the ported services. Tests pass a fake.
    struct Runtime {
        var startKill: @MainActor () -> Void
        var stopKill: @MainActor () -> Void
        var startPorts: @MainActor () -> Void
        var stopPorts: @MainActor () -> Void

        /// Live: nothing runs at rest, so nothing is armed and nothing is given back. A page forces a fresh read
        /// when it appears, so a list kept from before a stop is never what a kill acts on.
        static let live = Runtime(startKill: {}, stopKill: {}, startPorts: {}, stopPorts: {})
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(.killProcess, page: PortFeaturePage(pageID: "forcequit") { AnyView(KillProcessPage()) },
                     start: runtime.startKill, stop: runtime.stopKill)
        binding.bind(.portManager, page: PortFeaturePage(pageID: "ports") { AnyView(PortManagerPage()) },
                     start: runtime.startPorts, stop: runtime.stopPorts)
    }
}

// MARK: - Pages

/// Page 60: the ported process list, in a frame of its own height (the list scrolls inside).
private struct KillProcessPage: View {
    var body: some View {
        KillProcessView()
            .frame(height: 640)
            .islandGlass()
    }
}

/// Page 61: the ported ports list.
private struct PortManagerPage: View {
    var body: some View {
        PortManagerView()
            .frame(height: 560)
            .islandGlass()
    }
}
