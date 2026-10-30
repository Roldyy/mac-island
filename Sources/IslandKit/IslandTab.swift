import SwiftUI

/// What a feature module hands to the island: one tab with its view.
/// The contract is frozen for wave A: a feature exposes `tab()` plus its documented extras
/// (`claudeStatus()`, `idleView()`, `start()`); everything else stays internal to its module.
public struct IslandTab: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let makeView: @MainActor () -> AnyView

    public init(id: String, title: String, systemImage: String,
                makeView: @escaping @MainActor () -> AnyView) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.makeView = makeView
    }
}

/// Island services a tab view can call. Injected through the SwiftUI environment.
public struct IslandActions {
    /// Take the keyboard. Call after a click in a text field or the terminal, never on hover.
    public var focusKeyboard: @MainActor () -> Void
    /// Give the keyboard back and close the island.
    public var close: @MainActor () -> Void

    public init(focusKeyboard: @escaping @MainActor () -> Void = {},
                close: @escaping @MainActor () -> Void = {}) {
        self.focusKeyboard = focusKeyboard
        self.close = close
    }
}

private struct IslandActionsKey: EnvironmentKey {
    static let defaultValue = IslandActions()
}

public extension EnvironmentValues {
    var islandActions: IslandActions {
        get { self[IslandActionsKey.self] }
        set { self[IslandActionsKey.self] = newValue }
    }
}
