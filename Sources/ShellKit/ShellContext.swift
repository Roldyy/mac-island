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
public struct ShellContext {
    public var tabs: [IslandTab]
    public var registry: FeatureRegistry
    public var navigation: ShellNavigation
    public var quickAccess: QuickAccessModel
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
    /// Called with the visible section's tab id whenever it changes (per-tab open height).
    public var onSectionChange: @MainActor (String?) -> Void

    public init(tabs: [IslandTab], registry: FeatureRegistry, navigation: ShellNavigation,
                quickAccess: QuickAccessModel,
                closedStrip: @escaping @MainActor () -> AnyView = { AnyView(CompactStrip(layout: .empty)) },
                drawsLegacyAlertDot: Bool = true,
                onSectionChange: @escaping @MainActor (String?) -> Void = { _ in },
                alert: @escaping @MainActor () -> ShellAlert? = { nil },
                manualFansActive: @escaping @MainActor () -> Bool = { false },
                claudePill: @escaping @MainActor () -> AnyView = { AnyView(EmptyView()) },
                openSettings: @escaping @MainActor () -> Void = {},
                onOpen: @escaping @MainActor () -> Void = {}) {
        self.tabs = tabs
        self.registry = registry
        self.navigation = navigation
        self.quickAccess = quickAccess
        self.alert = alert
        self.manualFansActive = manualFansActive
        self.claudePill = claudePill
        self.openSettings = openSettings
        self.onOpen = onOpen
        self.closedStrip = closedStrip
        self.drawsLegacyAlertDot = drawsLegacyAlertDot
        self.onSectionChange = onSectionChange
    }
}
