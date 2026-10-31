import Foundation
import Observation

/// Which page is open, with back/forward history. The selection survives a relaunch.
@MainActor @Observable
public final class SettingsRouter {
    public static let selectionKey = "settings.selectedPage"

    public private(set) var selection: String
    public private(set) var back: [String] = []
    public private(set) var forward: [String] = []
    public var query = ""

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let validIDs: Set<String>

    public init(defaults: UserDefaults, pages: [SettingsPage] = SettingsPageCatalog.all) {
        self.defaults = defaults
        let ids = Set(pages.map(\.id))
        self.validIDs = ids
        let stored = defaults.string(forKey: Self.selectionKey)
        selection = stored.flatMap { ids.contains($0) ? $0 : nil } ?? SettingsPageCatalog.defaultPageID
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Opens a page and records the one left. An unknown id is ignored.
    public func open(_ id: String) {
        guard validIDs.contains(id), id != selection else { return }
        back.append(selection)
        forward.removeAll()
        selection = id
        defaults.set(id, forKey: Self.selectionKey)
    }

    public func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(selection)
        selection = previous
        defaults.set(previous, forKey: Self.selectionKey)
    }

    public func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(selection)
        selection = next
        defaults.set(next, forKey: Self.selectionKey)
    }
}
