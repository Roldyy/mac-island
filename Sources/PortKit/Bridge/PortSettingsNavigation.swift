// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Combine
import Foundation

/// Upstream's views navigate Settings through its own `SettingsRouter.shared` (a page, or a page and a section anchor) and
/// then call `appDelegate()?.openSettingsWindow()`. Nothing in Mac Island observes that router (our Settings window has its
/// own, in ShellKit), so every "Open Features", "Manage...", "Open Settings" button that sets a page did nothing but open
/// the window on whatever page was already showing.
///
/// This file is the seam: a pure mapping from upstream's pages and section anchors to OUR catalog page ids
/// (`SettingsPageCatalog`), and a small observer that forwards each router request to `AppDelegate.openSettingsPage`.
/// The upstream router file is not patched: its `@Published` values emit on every assignment, even to the same page.
enum PortSettingsNavigation {
    /// Our page for an upstream page, when no section anchor refines it.
    static func pageID(for page: SettingsPage) -> String {
        switch page {
        case .general: return "general"
        case .features: return "features"
        case .energy: return "keepawake"
        case .monitor: return "monitor"
        case .mouse: return "scrollreverse"
        case .switcher: return "switcher"
        case .dock: return "dockpreview"
        case .keyDebounce: return "debounce"
        case .superKey: return "superkey"
        case .cutPaste: return "cutpaste"
        case .autoQuit: return "quitonclose"
        case .quitProtection: return "quitprotect"
        case .cleaner: return "cleaner"
        case .uninstaller: return "uninstaller"
        case .urlCleaner: return "urlcleaner"
        case .homebrew: return "homebrew"
        case .appUpdates: return "appupdates"
        case .media: return "media"
        case .clipboard: return "clipboard"
        case .windowLayout: return "windowlayout"
        case .shelf: return "shelf"
        case .quickTools: return "quickpanel"
        case .textSnippets: return "snippets"
        case .screenshot: return "screenshot"
        case .radialMenu: return "radial"
        case .commandBar: return "commandbar"
        case .killProcess: return "forcequit"
        case .portManager: return "ports"
        case .notch: return "island"
        case .notchMascot: return "island"  // the companion's settings sit on the island page (and in its Compagnon tab)
        case .shortcuts: return "shortcuts"
        case .advanced: return "advanced"
        case .about: return "about"
        case .releaseNotes: return "whatsnew"
        case .support: return "support"
        }
    }

    /// Our page for a section of an upstream page: where Mac Island put that tool.
    static func pageID(for anchor: SettingsSectionAnchor) -> String {
        switch anchor {
        case .panelConfiguration: return "menubar"
        case .mixer: return "mixer"
        case .audioPriority: return "audiopriority"
        case .musicBlocking: return "musicblock"
        case .soundOutputSwitcher: return "outputswitch"
        case .keepAwake: return "keepawake"
        case .brightness: return "displays"
        case .extraBrightness: return "extrabrightness"
        case .bluetoothSleep: return "btsleep"
        case .scrollDirection: return "scrollreverse"
        case .focusFollowsMouse: return "focusfollows"
        case .smoothScroll: return "smoothscroll"
        case .linearScroll: return "linearscroll"
        case .mouseAcceleration: return "noaccel"
        case .mouseNavigation: return "sidebuttons"
        case .mouseButtonShortcuts: return "mouseshortcuts"
        case .middleClick: return "middleclick"
        case .mouseClickDebounce: return "clickfilter"
        case .switcher: return "switcher"
        case .dock: return "dockpreview"
        case .dockClick: return "dockclicks"
        case .spacesOrder: return "spaces"
        case .finderCutPaste: return "cutpaste"
        case .finderRename: return "renameshortcut"
        case .clipboardHistory: return "clipboard"
        case .pastePlain: return "pasteplain"
        case .quickLauncher: return "quickpanel"
        case .quickToggles: return "quickactions"
        case .screenshot: return "screenshot"
        case .screenRecorder: return "recording"
        case .colorPicker: return "colorpicker"
        case .screenOCR: return "ocr"
        case .micMute: return "mutemic"
        case .cameraPreview: return "camera"
        case .wallpaper: return "wallpaper"
        case .scratchpad: return "scratchpad"
        case .cleaningMode: return "cleaning"
        case .keyboardBrightnessShortcuts: return "kbdlight"
        case .fanControl: return "fans"
        case .windowMaximizer: return "maximize"
        }
    }

    /// The anchor wins when it is valid for the page; otherwise the page's own entry.
    static func pageID(for destination: FeatureSettingsDestination) -> String {
        if let anchor = destination.sectionAnchor, destination.hasValidSectionAnchor { return pageID(for: anchor) }
        return pageID(for: destination.page)
    }
}

/// Forwards every request made on an upstream `SettingsRouter` to the host. One per router; the app's lives in
/// `PortBridge.install`.
@MainActor
final class PortSettingsBridge {
    private enum Target {
        case page(SettingsPage)
        case destination(FeatureSettingsDestination)

        var pageID: String {
            switch self {
            case .page(let page): return PortSettingsNavigation.pageID(for: page)
            case .destination(let destination): return PortSettingsNavigation.pageID(for: destination)
            }
        }
    }

    static let shared = PortSettingsBridge(router: .shared, open: { id in appDelegate()?.openSettingsPage(id: id) })

    private let open: @MainActor (String) -> Void
    private var sinks: [AnyCancellable] = []
    private var target: Target?
    private var scheduled = false

    init(router: SettingsRouter, open: @escaping @MainActor (String) -> Void) {
        self.open = open
        // A request first sets the page (when it changes), then publishes its destination: only the last word counts,
        // so both only record the intent and one flush forwards it, after the caller's own statements.
        sinks.append(router.$page.dropFirst().sink { [weak self] page in
            MainActor.assumeIsolated { self?.note(.page(page)) }
        })
        sinks.append(router.$pendingDestinationRequest.sink { [weak self] request in
            guard let request else { return }
            MainActor.assumeIsolated { self?.note(.destination(request.destination)) }
        })
    }

    private func note(_ new: Target) {
        target = new
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.flush() } }
    }

    /// Forwards the pending intent now (the scheduled flush calls it; tests may too).
    func flush() {
        scheduled = false
        guard let pending = target else { return }
        target = nil
        open(pending.pageID)
    }
}
