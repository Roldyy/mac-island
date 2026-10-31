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
                relaunch: (@MainActor () -> Void)? = nil) {
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
    }

    // MARK: - Home actions

    /// Whether an action can run now: a quick action needs its handler, a page needs its feature on.
    public func isAvailable(_ action: HomeAction) -> Bool {
        switch action.kind {
        case .explore, .settings: true
        case .quick(let id): quickAccess.table.isAvailable(id)
        case .page(let tabID): tabs.contains { $0.id == tabID } && registry.isEnabled(tabID)
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
}
