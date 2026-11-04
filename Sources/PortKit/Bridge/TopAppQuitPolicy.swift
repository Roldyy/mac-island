// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation

/// Which apps the "Appli gourmande" chip never offers to quit. Pure: a name, a bundle identifier and process ids
/// in, a verdict out, so the list is tested without touching a process.
enum TopAppQuitPolicy {
    /// Lower-cased process or app names.
    static let refusedNames: Set<String> = [
        "finder", "dock", "loginwindow", "windowserver", "systemuiserver", "kernel_task", "controlcenter",
        "control center", "mac island", "macisland",
    ]

    /// Lower-cased bundle identifiers.
    static let refusedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.windowserver",
        "com.apple.systemuiserver", "com.apple.controlcenter", "be.roldy.macisland",
    ]

    /// True when the app must not get a Quit action: a system process of the list, the kernel or launchd (pid 1 and
    /// below), the app's own process (by pid or by bundle identifier).
    static func isRefused(name: String, bundleID: String?, pid: Int32, ownPID: Int32, ownBundleID: String?) -> Bool {
        if pid <= 1 || pid == ownPID { return true }
        if refusedNames.contains(name.trimmingCharacters(in: .whitespaces).lowercased()) { return true }
        if let bundleID {
            let id = bundleID.lowercased()
            if refusedBundleIDs.contains(id) { return true }
            if let ownBundleID, id == ownBundleID.lowercased() { return true }
        }
        return false
    }
}
