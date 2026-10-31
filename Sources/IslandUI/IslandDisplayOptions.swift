import SwiftUI
import AppKit

/// The three accessibility display switches the design system reacts to.
public struct IslandDisplayOptions: Equatable, Sendable {
    public var reduceTransparency: Bool
    public var increaseContrast: Bool
    public var reduceMotion: Bool

    public init(reduceTransparency: Bool = false, increaseContrast: Bool = false, reduceMotion: Bool = false) {
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.reduceMotion = reduceMotion
    }

    public static let standard = IslandDisplayOptions()

    /// A switch is on when either source says so.
    public func merged(with other: IslandDisplayOptions) -> IslandDisplayOptions {
        IslandDisplayOptions(
            reduceTransparency: reduceTransparency || other.reduceTransparency,
            increaseContrast: increaseContrast || other.increaseContrast,
            reduceMotion: reduceMotion || other.reduceMotion)
    }
}

/// Where the options come from. Tests inject a fixed value instead of the system.
public protocol IslandDisplayOptionsProviding: Sendable {
    var current: IslandDisplayOptions { get }
}

public struct SystemDisplayOptions: IslandDisplayOptionsProviding {
    public init() {}
    public var current: IslandDisplayOptions {
        let workspace = NSWorkspace.shared
        return IslandDisplayOptions(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}

public struct FixedDisplayOptions: IslandDisplayOptionsProviding {
    public let current: IslandDisplayOptions
    public init(_ options: IslandDisplayOptions) { current = options }
}

private struct IslandDisplayOptionsKey: EnvironmentKey {
    static let defaultValue: any IslandDisplayOptionsProviding = SystemDisplayOptions()
}

public extension EnvironmentValues {
    /// Injectable source of the display options; the system by default.
    var islandDisplayOptionsProvider: any IslandDisplayOptionsProviding {
        get { self[IslandDisplayOptionsKey.self] }
        set { self[IslandDisplayOptionsKey.self] = newValue }
    }
}

public extension View {
    /// Forces display options for this subtree (tests, previews, snapshots).
    func islandDisplayOptions(_ options: IslandDisplayOptions) -> some View {
        environment(\.islandDisplayOptionsProvider, FixedDisplayOptions(options))
    }
}

/// Reads the options inside a view: the provider, plus SwiftUI's own live environment values so
/// a change in System Settings is picked up without a relaunch. An injected fixed value wins alone.
struct IslandDisplay: DynamicProperty {
    @Environment(\.islandDisplayOptionsProvider) private var provider
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var options: IslandDisplayOptions {
        if provider is FixedDisplayOptions { return provider.current }
        let live = IslandDisplayOptions(
            reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased, reduceMotion: reduceMotion)
        return provider.current.merged(with: live)
    }
}
