import Foundation

/// Builds the one list of tiles the home grid and the Explorer both show. Pure: no view, no registry.
///
/// Order: 1) the user's actions, 2) every other enabled feature, 3) switched-off ones, dimmed, at the end.
/// An action and a feature that stand for the same thing (Claude and `agents`, Garder éveillé and `keepawake`,
/// Mélangeur and `audio`, Commandes and `commandbar`...) appear once, under the action's name and icon.
public enum HomeTileCatalog {
    /// Quick actions that open or drive a feature. A panel action already carries its tab id.
    static let quickActionFeatures: [String: String] = ["keepawake": "keepawake", "commands": "commandbar"]

    /// The feature an action stands for: its tab for a panel shortcut, the mapped feature for a quick action.
    public static func featureID(of action: HomeAction) -> String? {
        switch action.kind {
        case .page(let tabID): tabID
        case .quick(let id): quickActionFeatures[id]
        case .explore, .settings: nil
        }
    }

    /// Tile label: the action's title without its trailing ellipsis ("Réglages…" reads "Réglages").
    static func tileTitle(_ action: HomeAction) -> String {
        action.title.trimmingCharacters(in: CharacterSet(charactersIn: "…"))
    }

    /// - Parameters:
    ///   - actions: the user's tiles, first to last.
    ///   - features: every feature panel that exists (the registered tabs).
    ///   - enabled: whether a feature is switched on. A feature absent from `features` counts as off.
    ///   - hidden: tile ids the user hid. They leave the list unless `showHidden` is true (then they are flagged).
    public static func merged(actions: [HomeAction], features: [HomeFeature], enabled: (String) -> Bool,
                              hidden: Set<String>, showHidden: Bool = false) -> [HomeTileItem] {
        let present = Dictionary(features.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let order = ShellLayout.exploreTabIDs(available: features.map(\.id)) { _ in true }
        func isOn(_ featureID: String?) -> Bool {
            guard let featureID else { return true }
            return present[featureID] != nil && enabled(featureID)
        }

        var seen = Set<String>()
        var covered = Set<String>()
        var on: [HomeTileItem] = []
        var off: [HomeTileItem] = []
        func add(_ item: HomeTileItem) {
            if item.isEnabled { on.append(item) } else { off.append(item) }
        }

        for action in actions where seen.insert(action.id).inserted {
            let feature = featureID(of: action)
            if let feature { covered.insert(feature) }
            add(HomeTileItem(id: action.id, title: tileTitle(action), systemImage: action.systemImage,
                             source: .action(action), featureID: feature, isEnabled: isOn(feature),
                             isHidden: hidden.contains(action.id)))
        }
        for id in order where !covered.contains(id) {
            guard let feature = present[id], seen.insert(id).inserted else { continue }
            add(HomeTileItem(id: id, title: feature.title, systemImage: feature.systemImage, source: .feature,
                             featureID: id, isEnabled: isOn(id), isHidden: hidden.contains(id)))
        }

        // Switched-off tiles keep the Explorer's order among themselves, whichever group they came from.
        func rank(_ item: HomeTileItem) -> Int { item.featureID.flatMap(order.firstIndex(of:)) ?? order.count }
        let dimmed = off.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        return (on + dimmed).filter { showHidden || !$0.isHidden }
    }

    /// The items cut into rows of `columns` (the last row may be short).
    static func rows<T>(_ items: [T], columns: Int) -> [[T]] {
        guard columns > 0 else { return [] }
        return stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
    }
}
