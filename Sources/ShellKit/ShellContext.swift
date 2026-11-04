import CoreGraphics
import IslandKit
import SwiftUI

/// A system alert the island shows in its header while open.
public struct ShellAlert: Equatable, Sendable {
    public let title: String
    public let message: String
    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// Everything the island shell needs from the app, so ShellKit imports no feature module.
/// Closures that read observable feature state are called inside `body` and are tracked there.
@MainActor
public struct ShellContext {
    public var tabs: [IslandTab]
    public var registry: FeatureRegistry
    public var navigation: ShellNavigation
    public var quickAccess: QuickAccessModel
    /// Size, look, round buttons, sliders and now playing of the open island.
    public var home: HomeModel
    public var alert: @MainActor () -> ShellAlert?
    public var manualFansActive: @MainActor () -> Bool
    public var claudePill: @MainActor () -> AnyView
    public var openSettings: @MainActor () -> Void
    /// Runs each time the island opens.
    public var onOpen: @MainActor () -> Void
    /// The closed island's content. The app passes `CompactStrip` fed by the activity engine; read its
    /// observable state inside the closure so the shell redraws.
    public var closedStrip: @MainActor () -> AnyView
    /// Draw the hand-made red alert dot on the closed island. Turn off once the alert is an `IslandActivity`.
    public var drawsLegacyAlertDot: Bool
    /// Called with the visible page's tab id whenever it changes.
    public var onSectionChange: @MainActor (String?) -> Void
    /// The panel size the open island needs now (home size mode, Explorer or a page); the app resizes the panel.
    public var onOpenSize: @MainActor (CGSize) -> Void
    /// Quit and relaunch, for the island's right-click menu. `relaunch` is nil outside an app bundle.
    public var quit: @MainActor () -> Void
    public var relaunch: (@MainActor () -> Void)?
    /// Which switch opens a ported panel, and which panels exist only while it is on.
    public var tabGate: ShellTabGate
    /// Commands the app registered for the extra dock (the ported capture, recorder, OCR...).
    public var dockExtras: DockCommandRegistry
    /// Opens the Settings window on one page; nil falls back to `openSettings`.
    public var openSettingsPage: (@MainActor (String) -> Void)?
    /// Extra status chip sources the app registers (the ported monitor, calendar, timer...), added to the ones ShellKit
    /// feeds itself (network, load, disk). Evaluated once, when the context is built. A source of a kind ShellKit
    /// already feeds replaces it. ShellKit cannot import PortKit, so the app delegate fills this.
    public var statusSources: @MainActor () -> [any StatusChipSource]
    /// Temperature in degrees Celsius for the "Charge" chip, nil when unreadable. Read on the main actor each time the
    /// chip refreshes, only while the island is open.
    public var statusTemperature: (@MainActor () -> Double?)?
    /// Called when the "Charge" chip stops (the island closed), so whatever `statusTemperature` took is given back.
    public var statusTemperatureStop: (@MainActor () -> Void)?

    public init(tabs: [IslandTab], registry: FeatureRegistry, navigation: ShellNavigation,
                quickAccess: QuickAccessModel,
                home: HomeModel? = nil,
                closedStrip: @escaping @MainActor () -> AnyView = { AnyView(CompactStrip(layout: .empty)) },
                drawsLegacyAlertDot: Bool = true,
                onSectionChange: @escaping @MainActor (String?) -> Void = { _ in },
                alert: @escaping @MainActor () -> ShellAlert? = { nil },
                manualFansActive: @escaping @MainActor () -> Bool = { false },
                claudePill: @escaping @MainActor () -> AnyView = { AnyView(EmptyView()) },
                openSettings: @escaping @MainActor () -> Void = {},
                onOpen: @escaping @MainActor () -> Void = {},
                onOpenSize: @escaping @MainActor (CGSize) -> Void = { _ in },
                quit: @escaping @MainActor () -> Void = {},
                relaunch: (@MainActor () -> Void)? = nil,
                tabGate: ShellTabGate = .none,
                dockExtras: DockCommandRegistry? = nil,
                openSettingsPage: (@MainActor (String) -> Void)? = nil,
                statusSources: @escaping @MainActor () -> [any StatusChipSource] = { [] },
                statusTemperature: (@MainActor () -> Double?)? = nil,
                statusTemperatureStop: (@MainActor () -> Void)? = nil) {
        self.dockExtras = dockExtras ?? DockCommandRegistry()
        self.statusSources = statusSources
        self.statusTemperature = statusTemperature
        self.statusTemperatureStop = statusTemperatureStop
        self.openSettingsPage = openSettingsPage
        self.tabGate = tabGate
        self.tabs = tabs
        self.registry = registry
        self.navigation = navigation
        self.quickAccess = quickAccess
        self.home = home ?? HomeModel(defaults: .standard)
        self.alert = alert
        self.manualFansActive = manualFansActive
        self.claudePill = claudePill
        self.openSettings = openSettings
        self.onOpen = onOpen
        self.closedStrip = closedStrip
        self.drawsLegacyAlertDot = drawsLegacyAlertDot
        self.onSectionChange = onSectionChange
        self.onOpenSize = onOpenSize
        self.quit = quit
        self.relaunch = relaunch
        attachStatusSources()
    }

    /// Hands the feed its sources: the built-in ones, then the app's. The sources do nothing until the island opens.
    private func attachStatusSources() {
        let navigation = self.navigation
        var openMonitor: (@MainActor () -> Void)?
        if tabs.contains(where: { $0.id == "monitor" }) { openMonitor = { navigation.open(tabID: "monitor") } }
        home.statusChips.setSources(
            StatusChipProviders.builtin(openMonitor: openMonitor, temperature: statusTemperature,
                                        temperatureStop: statusTemperatureStop) + statusSources())
    }

    /// Whether the panel is on: its own switch, or the switches `tabGate` names for it.
    public func isTabEnabled(_ tabID: String) -> Bool {
        tabGate.isEnabled(tabID) { registry.isEnabled($0) }
    }

    // MARK: - Home actions

    /// Whether an action can run now: a quick action needs its handler, a page needs its feature on.
    public func isAvailable(_ action: HomeAction) -> Bool {
        switch action.kind {
        case .explore, .settings: true
        case .quick(let id): quickAccess.table.isAvailable(id)
        case .page(let tabID): tabs.contains { $0.id == tabID } && isTabEnabled(tabID)
        }
    }

    public func isOn(_ action: HomeAction) -> Bool {
        if case .quick(let id) = action.kind { return quickAccess.table.isOn(id) }
        return false
    }

    /// Runs a round button or a tile. Does nothing for an action that is not available.
    public func perform(_ action: HomeAction) {
        guard isAvailable(action) else { return }
        switch action.kind {
        case .explore: navigation.toggleExplore()
        case .settings: openSettings()
        case .quick(let id): quickAccess.table.fire(id)
        case .page(let tabID): navigation.open(tabID: tabID)
        }
    }

    // MARK: - Home tiles

    /// The tiles of the home grid (`showHidden: false`) or of the Explorer (`true`): one merged list, so the two
    /// screens never diverge. Reads the registry and the hidden set, so a view that calls it follows both.
    public func tileItems(showHidden: Bool = false) -> [HomeTileItem] {
        HomeTileCatalog.merged(
            actions: HomeActionCatalog.tileIDs.compactMap(HomeActionCatalog.action),
            // An optional panel (the ported extras) has no tile while its switch is off.
            features: tabs.filter { !tabGate.isOptional($0.id) || isTabEnabled($0.id) }
                .map { HomeFeature(id: $0.id, title: $0.title, systemImage: $0.systemImage) },
            enabled: { isTabEnabled($0) },
            hidden: home.hiddenTiles, showHidden: showHidden)
    }

    /// A tile is tappable unless it is a quick action with no handler. A switched-off feature stays tappable:
    /// the tap opens the Settings so it can be enabled.
    public func isAvailable(_ item: HomeTileItem) -> Bool {
        guard item.isEnabled, let action = item.action else { return true }
        return isAvailable(action)
    }

    public func isOn(_ item: HomeTileItem) -> Bool {
        guard item.isEnabled, let action = item.action else { return false }
        return isOn(action)
    }

    /// Runs a tile: opens the feature's page, fires the quick action, or opens the Settings for a switched-off one.
    public func perform(_ item: HomeTileItem) {
        guard item.isEnabled else { openSettings(); return }
        switch item.source {
        case .action(let action): perform(action)
        case .feature: navigation.open(tabID: item.id)
        }
    }
}
