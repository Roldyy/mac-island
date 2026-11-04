// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W9A (quick panel). The lane owns this file.

import AppKit
import ShellKit
import SwiftUI

/// The menu bar panel of the port: Vorssaint's `MenuPanelView` (keep awake, displays, mixer, system, network, disks,
/// energy, fans, utilities, controls, quick actions, wallpaper) hosted in a popover under Mac Island's own status
/// item. Our `MenuBarItemController` owns the item and the right-click menu; this class only owns the popover.
///
/// Nothing is built until the first click: no view, no monitor, no sampler. While the panel is open the ported
/// view asks `SystemMonitor` for its readings (`setMenuPanelNeeds`) and says "none" again when it disappears; closing
/// drops the content controller, so a closed panel keeps no view alive and nothing samples in the background.
///
/// Dismissal is the upstream policy reduced to its core: a click outside, Escape, or a click in another window of the
/// app closes the panel, EXCEPT while `PanelInteractionState.preventsPopoverDismissal` says a workflow spans clicks
/// (a running cleaner or uninstaller, a Homebrew operation, an alert or the AirPlay picker, a pinned tool).
@MainActor
public final class PortQuickPanel: NSObject, NSPopoverDelegate {
    public static let shared = PortQuickPanel()

    private let popover = NSPopover()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var anchor: NSView?

    /// Called right before the panel opens, so the host can close the island first.
    public var willShow: (() -> Void)?

    public var isShown: Bool { popover.isShown }

    override private init() {
        super.init()
        // Application-defined, never `.transient`: the policy below decides, so the panel can stay up while the
        // person works in Settings and watches a change take effect.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.hasFullSizeContent = PanelSurface.popoverHostsFullSizeContent
        popover.delegate = self
    }

    // MARK: - Show and hide

    /// A click on the status item: opens the panel, or closes it when it is open.
    public func toggle(from button: NSView) {
        if popover.isShown { close() } else { show(from: button) }
    }

    public func show(from button: NSView) {
        guard !popover.isShown else { return }
        willShow?()
        NotificationCenter.default.post(name: .menuPanelWillShow, object: nil)
        PanelInteractionState.shared.anchorScreen = button.window?.screen
        anchor = button
        let host = NSHostingController(rootView: MenuPanelView().defaultAppStorage(PortHost.defaults))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        MenuPanelFocus.shared.setPopoverVisible(popover.isShown)
        popover.contentViewController?.view.window?.makeKey()
        installMonitors()
    }

    /// Closes the panel. `force` also closes it while a workflow asked to keep it open (the app is quitting).
    public func close(force: Bool = false) {
        guard popover.isShown else { return }
        guard force || !PanelInteractionState.shared.preventsPopoverDismissal else { return }
        popover.close()
    }

    public func popoverDidClose(_ notification: Notification) {
        removeMonitors()
        MenuPanelFocus.shared.setPopoverVisible(false)
        PanelInteractionState.shared.viewKeepsPopoverOpen = false
        PanelInteractionState.shared.hostedSettingsPage = nil
        PanelInteractionState.shared.anchorScreen = nil
        // Drops the view tree: its `onDisappear` tells the system monitor nothing is needed any more.
        popover.contentViewController = nil
        anchor = nil
    }

    // MARK: - Dismissal policy

    /// Pure: whether an event at `window` (nil = another app) closes the panel. The panel's own window never does,
    /// and neither does the status item's window (its action toggles, a close here would reopen it at once).
    static func dismisses(clickIn window: NSWindow?, panelWindow: NSWindow?, anchorWindow: NSWindow?) -> Bool {
        guard let window else { return true }
        return window !== panelWindow && window !== anchorWindow
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            // The event itself never enters the isolated closure (NSEvent is not Sendable): only what is read from it.
            let type = event.type, code = event.keyCode, window = event.window
            let swallow = MainActor.assumeIsolated { self?.handleLocal(type: type, keyCode: code, window: window) ?? false }
            return swallow ? nil : event
        }
    }

    /// True when the event is consumed (Escape closed the panel).
    private func handleLocal(type: NSEvent.EventType, keyCode: UInt16, window: NSWindow?) -> Bool {
        guard popover.isShown else { return false }
        if type == .keyDown {
            guard keyCode == 53 else { return false }  // Escape
            close()
            return !popover.isShown  // a pinned workflow keeps the panel up and gets the key
        }
        let panelWindow = popover.contentViewController?.view.window
        if Self.dismisses(clickIn: window, panelWindow: panelWindow, anchorWindow: anchor?.window) { close() }
        return false
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}

// MARK: - Page "Barre des menus"

/// The body of Settings page `menubar`: which sections the panel shows, in which order, and the icon in the menu bar.
/// It is the upstream panel configuration card; the "icon is missing" row is left out. The one switch that shows or
/// hides Mac Island's status item (`MenuBarIconPolicy`, hidden by default) sits at the top of the card.
///
/// Page 02 also carries the live menu bar metrics (CPU, memory, network...): those belong to the monitor lane and are
/// added there, next to this card, by registering a composite body for the same page id.
struct MenuBarPanelPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(MenuBarIconPolicy.key) private var iconShown = false

    private var text: GeneralSettingsStrings { FeatureStrings.generalSettings(l10n.language) }

    var body: some View {
        SettingsCard(title: l10n.s.menuBarSection) {
            Toggle("Afficher l’icône Mac Island dans la barre des menus", isOn: $iconShown)
            Text("Désactivée par défaut : tout est dans l’île. Le panneau rapide s’ouvre depuis cette icône.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(text.panelIntro)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PanelLayoutEditor()
            Divider()
            MenuBarIconSymbolRow()
        }
    }
}

enum QuickPanelLane {
    static let pageID = "menubar"

    @MainActor static func bind(into binding: PortFeatureBinding) {
        PortBridge.register(pageID: pageID) { AnyView(MenuBarPanelPage().defaultAppStorage(PortHost.defaults)) }
    }
}
