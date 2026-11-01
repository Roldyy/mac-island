// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W6B (panels and menu bar metrics). The lane owns this file.

import AppKit
import Combine
import IslandUI
import SwiftUI

// MARK: - What the bar shows

/// The status items the pinned metrics need right now. Pure: the defaults in, the list out.
///
/// Upstream drew the metrics next to its icon, in the one item it owned (`StatusItemController`, not imported: Mac
/// Island's `MenuBarItemController` owns the icon). The metrics therefore always sit in items of their own: one item
/// for every pinned metric, or one per group when the person chose "Séparer les mesures en éléments dédiés"
/// (upstream's own split, which keeps a usage and its temperature together when they are combined).
struct MenuBarMetricsPlan: Equatable {
    struct Item: Equatable {
        let id: String
        let metrics: [MenuBarMetric]
        /// The metric whose detail a click opens.
        let focus: MenuBarMetric
    }

    var items: [Item] = []

    static func make(defaults: UserDefaults, strings: Strings) -> MenuBarMetricsPlan {
        let metrics = MenuBarMetric.enabled(in: defaults)
        guard let first = metrics.first else { return MenuBarMetricsPlan() }
        guard defaults.bool(forKey: DefaultsKey.menuBarSeparateMetrics) else {
            return MenuBarMetricsPlan(items: [Item(id: "metrics", metrics: metrics, focus: first)])
        }
        return MenuBarMetricsPlan(items: StatusItemController.metricStatusGroups(for: metrics, strings: strings).map {
            Item(id: "metric.\($0.id)", metrics: $0.metrics, focus: $0.focusMetric)
        })
    }
}

// MARK: - The host

/// One status item the host draws a title in. The live one wraps an `NSStatusItem`; tests pass a recorder.
@MainActor
protocol MenuBarMetricSurface: AnyObject {
    func show(title: NSAttributedString)
    func remove()
}

/// Where a metric's detail opens. The live one is an `NSPopover` under the item; tests pass a recorder.
@MainActor
protocol MenuBarMetricDetailPresenter: AnyObject {
    var onClose: (() -> Void)? { get set }
    var isShown: Bool { get }
    func show(kind: MetricDetailKind, below surface: MenuBarMetricSurface, setNeeds: @escaping (SystemMonitorPanelNeeds) -> Void)
    func close()
}

/// Draws the pinned metrics in the menu bar and opens their detail. It owns nothing the registry owns: it exists
/// only while at least one monitor family is on and at least one metric is pinned, samples only through
/// `SystemMonitor.setMenuBarActive` (which stops the moment the last item goes), and writes no preference.
///
/// `sync()` is idempotent and cheap: the monitor lane calls it on every start and stop of a family, and the live
/// host calls it again on each preference change and each new sample.
@MainActor
final class MenuBarMetricsHost: NSObject {
    static let shared = MenuBarMetricsHost()

    /// What the host needs from outside. Tests replace all of it: no status bar, no sampler, no popover.
    struct Environment {
        var defaults: @MainActor () -> UserDefaults
        var strings: @MainActor () -> Strings
        var snapshot: @MainActor () -> SystemSnapshot
        var setMenuBarActive: @MainActor (Bool) -> Void
        var setPanelNeeds: @MainActor (SystemMonitorPanelNeeds) -> Void
        var makeSurface: @MainActor (_ id: String, _ click: @escaping @MainActor (MenuBarMetricSurface, NSEvent?) -> Void) -> MenuBarMetricSurface
        var makePresenter: @MainActor () -> MenuBarMetricDetailPresenter
        var openSettings: @MainActor () -> Void
        var quit: @MainActor () -> Void
        var now: @MainActor () -> TimeInterval

        static let live = Environment(
            defaults: { PortHost.defaults },
            strings: { L10n.shared.s },
            snapshot: { SystemMonitor.shared.snapshot },
            setMenuBarActive: { SystemMonitor.shared.setMenuBarActive($0) },
            setPanelNeeds: { SystemMonitor.shared.setMenuPanelNeeds($0) },
            makeSurface: { id, click in StatusItemMetricSurface(id: id, click: click) },
            makePresenter: { MetricDetailPopover() },
            openSettings: { appDelegate()?.openSettingsWindow() },
            quit: { NSApp.terminate(nil) },
            now: { ProcessInfo.processInfo.systemUptime })
    }

    /// Entries of the context menu (right click). The menu and its test share it.
    static let menuTitles = ["Ouvrir Réglages…", "Quitter Mac Island"]

    var environment: Environment
    /// The host's way to show or hide the app's own icon (`PortMenuBar.installAppIconVisibility`).
    private var appIconVisibility: (@MainActor (Bool) -> Void)?

    private(set) var plan = MenuBarMetricsPlan()
    private var surfaces: [String: MenuBarMetricSurface] = [:]
    private var emptyStreak: [String: Int] = [:]
    private var presenter: MenuBarMetricDetailPresenter?
    private var openKind: MetricDetailKind?
    private var closedAt: (kind: MetricDetailKind, at: TimeInterval)?
    private var iconHidden = false
    private var snapshotSink: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var syncScheduled = false

    init(environment: Environment = .live) {
        self.environment = environment
        super.init()
    }

    /// The ids of the items on screen, in plan order (tests).
    var itemIDs: [String] { plan.items.map(\.id).filter { surfaces[$0] != nil } }

    var isAppIconHidden: Bool { iconHidden }

    // MARK: Sync

    func sync() {
        let env = environment
        let defaults = env.defaults()
        plan = MenuBarMetricsPlan.make(defaults: defaults, strings: env.strings())
        let wanted = Set(plan.items.map(\.id))
        for id in Array(surfaces.keys) where !wanted.contains(id) {
            surfaces.removeValue(forKey: id)?.remove()
            emptyStreak[id] = nil
        }
        env.setMenuBarActive(!plan.items.isEmpty)
        guard !plan.items.isEmpty else {
            closeDetail()
            applyIconVisibility(shown: 0, defaults: defaults)
            return
        }
        render()
    }

    /// Redraws every title from the latest sample.
    func render() {
        let env = environment
        let defaults = env.defaults()
        let snapshot = env.snapshot()
        var shown = 0
        for item in plan.items {
            let title = Self.title(for: item, snapshot: snapshot)
            let hasTitle = title.length > 0
            let streak = hasTitle ? 0 : (emptyStreak[item.id] ?? 0) + 1
            emptyStreak[item.id] = streak
            if MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: hasTitle, itemExists: surfaces[item.id] != nil,
                                                          consecutiveEmptyRenders: streak) {
                let surface = surfaces[item.id] ?? makeSurface(for: item)
                surface.show(title: title)
                if hasTitle { shown += 1 }
            } else if let gone = surfaces.removeValue(forKey: item.id) {
                gone.remove()
            }
        }
        applyIconVisibility(shown: shown, defaults: defaults)
    }

    static func title(for item: MenuBarMetricsPlan.Item, snapshot: SystemSnapshot) -> NSAttributedString {
        let drawn = NSMutableAttributedString(attributedString: MenuBarRenderer.attributed(for: snapshot, metrics: item.metrics))
        if drawn.length > 0 {
            drawn.addAttribute(.font, value: MenuBarRenderer.statusFont(stacked: false),
                               range: NSRange(location: 0, length: drawn.length))
        }
        return drawn
    }

    private func makeSurface(for item: MenuBarMetricsPlan.Item) -> MenuBarMetricSurface {
        let id = item.id
        let surface = environment.makeSurface(id) { [weak self] surface, event in
            self?.handleClick(on: id, surface: surface, event: event)
        }
        surfaces[id] = surface
        return surface
    }

    /// Gives the host its icon hook. The icon is made visible at once (a hidden state a crashed run left behind
    /// never survives a launch), then the hide rule runs again against what is on screen: the registry may have
    /// started the families before the app had an icon to lend.
    func installAppIconVisibility(_ setVisible: (@MainActor (Bool) -> Void)?) {
        appIconVisibility = setVisible
        iconHidden = false
        setVisible?(true)
        if !plan.items.isEmpty { render() }
    }

    /// The app icon hides only while at least one metric item shows something, and only when the person asked
    /// (`menuBarHideIconWithMetrics`). With no item on screen it is always back, so it can never be lost.
    private func applyIconVisibility(shown: Int, defaults: UserDefaults) {
        let hide = MenuBarSpacingSupport.shouldHideMainStatusItem(
            optionEnabled: defaults.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics),
            separateMetrics: true, metricItemsShown: shown, renderedTitleLength: 0, mustShowForSignal: false)
        guard hide != iconHidden else { return }
        iconHidden = hide
        appIconVisibility?(!hide)
    }

    // MARK: Clicks

    func handleClick(on id: String, surface: MenuBarMetricSurface, event: NSEvent?) {
        guard let item = plan.items.first(where: { $0.id == id }) else { return }
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false) {
            closeDetail()
            showMenu(from: surface)
            return
        }
        toggleDetail(for: item.focus.detailKind, below: surface)
    }

    func toggleDetail(for kind: MetricDetailKind, below surface: MenuBarMetricSurface) {
        let env = environment
        if let presenter, presenter.isShown {
            let same = openKind == kind
            closeDetail()
            if same { return }
        } else if let closedAt, closedAt.kind == kind, env.now() - closedAt.at < 0.3 {
            // A transient popover closes on the mouse-down of the very click that would reopen it.
            self.closedAt = nil
            return
        }
        let presenter = self.presenter ?? env.makePresenter()
        presenter.onClose = { [weak self] in self?.detailClosed() }
        self.presenter = presenter
        openKind = kind
        env.setPanelNeeds(kind.monitorNeeds)
        presenter.show(kind: kind, below: surface, setNeeds: { env.setPanelNeeds($0) })
    }

    func closeDetail() {
        guard let presenter, presenter.isShown else { return }
        presenter.close()
        detailClosed()
    }

    private func detailClosed() {
        guard let kind = openKind else { return }
        openKind = nil
        closedAt = (kind, environment.now())
        environment.setPanelNeeds(.none)
    }

    private func showMenu(from surface: MenuBarMetricSurface) {
        guard let surface = surface as? StatusItemMetricSurface else { return }
        let menu = NSMenu()
        let settings = NSMenuItem(title: Self.menuTitles[0], action: #selector(menuOpenSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: Self.menuTitles[1], action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        surface.popUp(menu)
    }

    @objc private func menuOpenSettings() { environment.openSettings() }
    @objc private func menuQuit() { environment.quit() }

    // MARK: Live observers

    /// Preference changes and new samples redraw the bar. Installed by the live runtime only, once.
    func installLiveObservers() {
        guard defaultsObserver == nil else { return }
        let defaults = environment.defaults()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
        snapshotSink = SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.snapshotArrived() } }
    }

    private func snapshotArrived() {
        guard !plan.items.isEmpty else { return }
        render()
    }

    private func scheduleSync() {
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncScheduled = false
                self.sync()
            }
        }
    }
}

// MARK: - Live status item and popover

/// One `NSStatusItem` that shows an attributed title and reports clicks (left and right).
@MainActor
final class StatusItemMetricSurface: NSObject, MenuBarMetricSurface {
    private let item: NSStatusItem
    private let click: @MainActor (MenuBarMetricSurface, NSEvent?) -> Void

    init(id: String, click: @escaping @MainActor (MenuBarMetricSurface, NSEvent?) -> Void) {
        self.click = click
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = "be.roldy.macisland.metrics.\(id)"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    var button: NSStatusBarButton? { item.button }

    func show(title: NSAttributedString) {
        item.button?.attributedTitle = title
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    func popUp(_ menu: NSMenu) {
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil  // a standing menu would swallow the next left click
    }

    @objc private func clicked() {
        click(self, NSApp.currentEvent)
    }
}

@MainActor
final class MetricDetailPopover: NSObject, MenuBarMetricDetailPresenter, NSPopoverDelegate {
    var onClose: (() -> Void)?
    private var popover: NSPopover?

    var isShown: Bool { popover?.isShown ?? false }

    func show(kind: MetricDetailKind, below surface: MenuBarMetricSurface,
              setNeeds: @escaping (SystemMonitorPanelNeeds) -> Void) {
        guard let button = (surface as? StatusItemMetricSurface)?.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: MenuBarMetricPopover.width, height: MenuBarMetricPopover.height)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarMetricPopover(kind: kind, setNeeds: setNeeds).defaultAppStorage(PortHost.defaults))
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        popover?.contentViewController = nil  // the SwiftUI views see their onDisappear
        popover = nil
        onClose?()
    }
}

// MARK: - The popover content

/// What a click on a pinned metric opens: the metric's detail (upstream's metric panel) and, one tap away, the
/// whole section it belongs to (System, Network, Disks, Energy). The popover itself is the system's frosted glass.
struct MenuBarMetricPopover: View {
    static let width: CGFloat = 340
    static let height: CGFloat = 520

    @State private var kind: MetricDetailKind
    @State private var showsSection = false
    @ObservedObject private var l10n = L10n.shared
    let setNeeds: (SystemMonitorPanelNeeds) -> Void

    init(kind: MetricDetailKind, setNeeds: @escaping (SystemMonitorPanelNeeds) -> Void) {
        _kind = State(initialValue: kind)
        self.setNeeds = setNeeds
    }

    /// The section a metric belongs to, when the panel has one (fans live on the fans page).
    static func sectionNeeds(for kind: MetricDetailKind) -> SystemMonitorPanelNeeds? {
        switch kind.panelSection {
        case .system: SystemMonitorPanelNeeds(system: true)
        case .network: SystemMonitorPanelNeeds(network: true)
        case .disk: SystemMonitorPanelNeeds(disk: true)
        case .power: SystemMonitorPanelNeeds(power: true, powerCard: true)
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            HStack(spacing: IslandSpacing.s) {
                Image(systemName: kind.symbolName)
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .accessibilityHidden(true)
                Text(kind.title(l10n.s))
                    .font(.islandBodyEmphasis)
                    .foregroundStyle(IslandPalette.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if Self.sectionNeeds(for: kind) != nil {
                    Button(showsSection ? "Détail" : "Panneau") { showsSection.toggle() }
                        .buttonStyle(IslandButtonStyle())
                }
                ActivityMonitorButton()
            }
            ScrollView {
                content
                    .frame(width: Self.width - 32)
            }
        }
        .padding(IslandSpacing.m)
        .frame(width: Self.width, height: Self.height, alignment: .top)
        .onChange(of: showsSection) { _, _ in applyNeeds() }
        .onChange(of: kind) { _, _ in applyNeeds() }
    }

    @ViewBuilder private var content: some View {
        if showsSection, let _ = Self.sectionNeeds(for: kind) {
            switch kind.panelSection {
            case .system:
                SystemSection(collapsible: false) { kind = .connectedDevices; showsSection = false }
            case .network: NetworkSection(collapsible: false)
            case .disk: DiskSection(collapsible: false)
            case .power: PowerSection(collapsible: false)
            default: MetricDetailView(kind: kind)
            }
        } else {
            MetricDetailView(kind: kind)
        }
    }

    private func applyNeeds() {
        if showsSection, let needs = Self.sectionNeeds(for: kind) { setNeeds(needs) } else { setNeeds(kind.monitorNeeds) }
    }
}

// MARK: - Host hooks

/// What the app delegate may lend to the metrics host.
public enum PortMenuBar {
    /// How the host shows or hides the app's own menu bar icon (the "Masquer l'icône de l'app" option). Passing a
    /// closure makes the icon visible at once: a hidden state a crashed run left behind never survives a launch.
    /// Nil removes the hook (the icon is then never touched).
    @MainActor
    public static func installAppIconVisibility(_ setVisible: (@MainActor (Bool) -> Void)?) {
        MenuBarMetricsHost.shared.installAppIconVisibility(setVisible)
    }
}
