import Foundation
import Observation

/// One button of the quick-access bar.
public struct QuickAccessItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Short label under the icon; the full title is the tooltip and the VoiceOver label.
    public let shortTitle: String
    public let systemImage: String
}

public enum QuickAccessCatalog {
    public static let items: [QuickAccessItem] = [
        QuickAccessItem(id: "commands", title: "Commandes", shortTitle: "Commandes", systemImage: "command"),
        QuickAccessItem(id: "capture", title: "Capture", shortTitle: "Capture", systemImage: "camera.viewfinder"),
        QuickAccessItem(id: "lockScreen", title: "Verrouiller l'écran", shortTitle: "Verrouiller", systemImage: "lock"),
        QuickAccessItem(id: "cleaning", title: "Mode nettoyage", shortTitle: "Nettoyage", systemImage: "sparkles.rectangle.stack"),
        QuickAccessItem(id: "keepawake", title: "Éveil", shortTitle: "Éveil", systemImage: "cup.and.saucer"),
        QuickAccessItem(id: "settings", title: "Réglages", shortTitle: "Réglages", systemImage: "gearshape"),
    ]
    public static let defaultIDs = items.map(\.id)
    public static let maxCount = 6

    /// Known ids only, no duplicates, at most six; an empty result falls back to the defaults.
    public static func sanitized(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        let known = Set(items.map(\.id))
        let kept = ids.filter { known.contains($0) && seen.insert($0).inserted }.prefix(maxCount)
        return kept.isEmpty ? defaultIDs : Array(kept)
    }

    public static func item(_ id: String) -> QuickAccessItem? { items.first { $0.id == id } }
}

/// Maps a quick-access id to what it does. The shell injects only what exists; a missing action
/// leaves its button dimmed instead of failing.
@MainActor @Observable
public final class QuickActionTable {
    @ObservationIgnored private var actions: [String: @MainActor () -> Void] = [:]
    /// Bumped on every registration so views re-read `isAvailable`.
    public private(set) var revision = 0

    public init() {}

    public func register(_ id: String, _ action: @escaping @MainActor () -> Void) {
        actions[id] = action
        revision += 1
    }

    public func isAvailable(_ id: String) -> Bool { _ = revision; return actions[id] != nil }

    @discardableResult
    public func fire(_ id: String) -> Bool {
        guard let action = actions[id] else { return false }
        action()
        return true
    }
}

/// The configurable list of ids, persisted in the app's defaults.
@MainActor @Observable
public final class QuickAccessModel {
    static let key = "shell.quickAccess.ids"

    public var ids: [String] { didSet { defaults.set(ids, forKey: Self.key) } }
    @ObservationIgnored private let defaults: UserDefaults
    public let table: QuickActionTable

    public init(defaults: UserDefaults, table: QuickActionTable? = nil) {
        self.defaults = defaults
        self.table = table ?? QuickActionTable()
        self.ids = QuickAccessCatalog.sanitized(defaults.stringArray(forKey: Self.key) ?? [])
    }

    public var items: [QuickAccessItem] { ids.compactMap(QuickAccessCatalog.item) }

    public func setIDs(_ new: [String]) { ids = QuickAccessCatalog.sanitized(new) }
}
