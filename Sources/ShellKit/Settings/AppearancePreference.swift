import AppKit
import Foundation

/// Light, dark or follow the system. Applies to every window and panel of the app, not to the rest of the Mac.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public static let key = "appAppearance"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    public var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `nil` hands the choice back to the system.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    public static func load(from defaults: UserDefaults) -> AppearancePreference {
        defaults.string(forKey: key).flatMap(AppearancePreference.init(rawValue:)) ?? .system
    }

    public func save(to defaults: UserDefaults) { defaults.set(rawValue, forKey: Self.key) }

    @MainActor public func apply() { NSApp?.appearance = nsAppearance }
}
