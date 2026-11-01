// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W3D (auto-quit and Spaces). The lane owns this file.

import AppKit
import ApplicationServices
import Foundation

// MARK: - Policy (pure)

/// Why an app is never asked to quit. One value per rule, so a test (and the page) can name the rule that held.
enum AutoQuitVeto: Equatable {
    /// No bundle identifier: nothing to match a list against, so nothing to decide on.
    case noIdentity
    case ownApp
    case finder
    /// Dock, login window, Control Center, Spotlight...: the system's own UI.
    case system
    /// The person's own never-quit list (it also holds the mandatory entries, Finder and Phone).
    case neverQuitList
    case notRegular
    case playingAudio
    /// A Save or Open panel, a sheet or a dialog is up: closing the app would drop what the person is saving.
    case openPanel
    /// The app in front. Only the inactivity path holds it (see `AutoQuitSafety.Path`).
    case frontmost
}

/// The decision behind every automatic quit, kept apart from the system calls so each rule can be walked with
/// plain values. The caller supplies the facts; the live ones are autoclosures, read only when an earlier rule
/// did not already settle the answer (the audio and Accessibility reads are not free).
///
/// It decides WHETHER an app may be asked to quit. How is never in question: the only call that ends an app is
/// `NSRunningApplication.terminate()`, the polite one (the app may show "Save changes?" and cancel). No forced
/// quit, no signal, no `kill`, anywhere in the auto-quit code; `AutoQuitSafetyTests` scans for it.
enum AutoQuitSafety {
    enum Path: Equatable {
        /// The last window of an app was closed. The app is usually still the frontmost one at that moment (the
        /// person just clicked its red button), so being in front cannot veto here, or the feature would never
        /// fire. Everything else does.
        case lastWindow
        /// The app has had no window for a long while. Being in front always vetoes.
        case inactivity
    }

    /// The system's own processes. Never listed for the person to remove, never quit.
    static let systemBundleIDs: Set<String> = [
        "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver", "com.apple.controlcenter",
        "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.WindowManager",
    ]

    static let finderBundleID = "com.apple.finder"
    /// Mac Island itself, whatever the running bundle is called (`swift run` has another id).
    static let ownBundleID = "be.roldy.macisland"

    /// The first rule that holds, nil when the app may be asked to quit. The order is the order of the list on
    /// the Settings page: identity first, then the app's state.
    static func veto(pid: Int32, bundleID: String?, isRegular: Bool, path: Path,
                     ownPID: Int32, ownBundleIDs: Set<String>, neverQuit: Set<String>,
                     isFrontmost: @autoclosure () -> Bool,
                     isPlayingAudio: @autoclosure () -> Bool,
                     hasOpenPanel: @autoclosure () -> Bool) -> AutoQuitVeto? {
        if pid == ownPID { return .ownApp }
        guard let bundleID, !bundleID.isEmpty else { return .noIdentity }
        if ownBundleIDs.contains(bundleID) || bundleID == ownBundleID { return .ownApp }
        if bundleID == finderBundleID { return .finder }
        if systemBundleIDs.contains(bundleID) { return .system }
        if neverQuit.contains(bundleID) { return .neverQuitList }
        if !isRegular { return .notRegular }
        if isPlayingAudio() { return .playingAudio }
        if hasOpenPanel() { return .openPanel }
        if path == .inactivity, isFrontmost() { return .frontmost }
        return nil
    }
}

// MARK: - Open panels (Accessibility facts, judged here)

/// What the Accessibility tree says about one window of an app, reduced to what the panel check needs.
struct AutoQuitAXWindow: Equatable {
    var role: String?
    var subrole: String?
    var isModal: Bool
    /// The window carries a sheet (a Save panel attached to a document window is one).
    var hasSheet: Bool

    init(role: String? = nil, subrole: String? = nil, isModal: Bool = false, hasSheet: Bool = false) {
        self.role = role
        self.subrole = subrole
        self.isModal = isModal
        self.hasSheet = hasSheet
    }
}

enum AutoQuitPanelCheck {
    static let dialogSubroles: Set<String> = ["AXDialog", "AXSystemDialog"]

    /// True when any window is a dialog, a sheet, modal, or carries a sheet.
    static func hasBlockingPanel(_ windows: [AutoQuitAXWindow]) -> Bool {
        windows.contains { window in
            window.isModal || window.hasSheet || window.role == "AXSheet"
                || window.subrole.map(dialogSubroles.contains) == true
        }
    }
}

/// The Accessibility reads of the panel check, injectable. Fakes stand in for them in tests.
protocol AutoQuitAXReading {
    /// Every window of the app, standard or not. Empty when Accessibility cannot answer (the caller then relies
    /// on the window-server check the upstream service already makes before it gets here).
    func windows(of pid: Int32) -> [AutoQuitAXWindow]
}

/// The live reader: bounded Accessibility calls (0.35 s) on the main thread, windows only (never the
/// application element's role, which flips a Chromium app into full accessibility mode, upstream issue #953).
struct LiveAutoQuitAXReader: AutoQuitAXReading {
    func windows(of pid: Int32) -> [AutoQuitAXWindow] {
        guard AXIsProcessTrusted() else { return [] }  // read-only: no options dictionary, so no prompt
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.map { window in
            AXUIElementSetMessagingTimeout(window, 0.35)
            return AutoQuitAXWindow(
                role: Self.string(window, kAXRoleAttribute),
                subrole: Self.string(window, kAXSubroleAttribute),
                isModal: Self.bool(window, "AXModal"),
                hasSheet: Self.hasSheetChild(window))
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private static func hasSheetChild(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return false }
        return children.contains { string($0, kAXRoleAttribute) == "AXSheet" }
    }
}

// MARK: - Live gate

/// The system facts the policy reads, as closures: the live set reads NSWorkspace, CoreAudio and Accessibility;
/// tests pass fakes (a fake workspace, fake AX windows, a fake audio list).
struct AutoQuitEnvironment {
    var ownPID: () -> Int32
    var ownBundleIDs: () -> Set<String>
    var neverQuit: () -> Set<String>
    var frontmostPID: () -> Int32?
    var isRegular: (Int32) -> Bool
    var isPlayingAudio: (Int32) -> Bool
    var ax: AutoQuitAXReading

    static var live: AutoQuitEnvironment {
        AutoQuitEnvironment(
            ownPID: { ProcessInfo.processInfo.processIdentifier },
            ownBundleIDs: { Set([Bundle.main.bundleIdentifier, AutoQuitSafety.ownBundleID].compactMap { $0 }) },
            neverQuit: { Set(Defaults.sanitizedAutoQuitExceptions(
                PortHost.defaults.stringArray(forKey: DefaultsKey.autoQuitExceptions) ?? [])) },
            frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            isRegular: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular },
            isPlayingAudio: { AutoQuitAudio.isPlaying(pid: $0) },
            ax: LiveAutoQuitAXReader())
    }
}

/// The last check before the upstream service asks an app to quit (patch 0850): it vetoes on the same rules as
/// the inactivity path, minus "in front". Nothing here quits anything or prompts.
struct AutoQuitGate {
    var environment: AutoQuitEnvironment

    static let live = AutoQuitGate(environment: .live)

    func veto(pid: Int32, bundleID: String?, path: AutoQuitSafety.Path) -> AutoQuitVeto? {
        let env = environment
        return AutoQuitSafety.veto(
            pid: pid, bundleID: bundleID, isRegular: env.isRegular(pid), path: path,
            ownPID: env.ownPID(), ownBundleIDs: env.ownBundleIDs(), neverQuit: env.neverQuit(),
            isFrontmost: env.frontmostPID() == pid,
            isPlayingAudio: env.isPlayingAudio(pid),
            hasOpenPanel: AutoQuitPanelCheck.hasBlockingPanel(env.ax.windows(of: pid)))
    }

    /// True when the last-window path may ask this app to quit.
    func allowsLastWindowQuit(pid: Int32, bundleID: String?) -> Bool {
        veto(pid: pid, bundleID: bundleID, path: .lastWindow) == nil
    }

    func allowsLastWindowQuit(_ app: NSRunningApplication) -> Bool {
        allowsLastWindowQuit(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
    }
}
