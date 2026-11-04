// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation

/// How a chip's action reaches an island tab. The tests pass a recorder; live, the door is the app delegate's
/// `openIslandTab` hook (bound by `PortBridge.connectIsland`), so a missing binding means "not reachable".
struct StatusChipNavigator {
    var isAvailable: @MainActor () -> Bool
    var open: @MainActor (_ tabID: String) -> Void

    @MainActor static let live = StatusChipNavigator(
        isAvailable: { AppDelegate.current?.openIslandTab != nil },
        open: { AppDelegate.current?.openIslandTab(id: $0) })
}
