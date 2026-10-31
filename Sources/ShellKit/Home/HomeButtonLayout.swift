import Foundation

public enum HomeButtonSide: String, Codable, CaseIterable, Sendable {
    case left, right, bottom

    public var title: String {
        switch self {
        case .left: "Gauche"
        case .right: "Droite"
        case .bottom: "En bas"
        }
    }
}

/// One round button around the island.
public struct HomeButton: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var actionID: String
    public var side: HomeButtonSide
    /// Optional name; empty means icon only.
    public var label: String

    public init(id: UUID = UUID(), actionID: String, side: HomeButtonSide, label: String = "") {
        self.id = id
        self.actionID = actionID
        self.side = side
        self.label = label
    }
}

/// The user's round buttons: at most three per side, no action twice, order = order in `buttons`.
/// Stored as `{"version":1,"buttons":[{"id","actionID","side","label"}]}` under the island layout key.
public struct HomeButtonLayout: Codable, Equatable, Sendable {
    public static let version = 1
    public static let maxPerSide = 3

    public var buttons: [HomeButton]

    public init(buttons: [HomeButton]) { self.buttons = buttons }

    /// Left: Explorer, Presse-papiers, Claude. Right: Réglages, Mélangeur. Bottom: Commandes, Garder éveillé.
    public static let initial = HomeButtonLayout(buttons: [
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000001")!, actionID: "explore", side: .left),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000002")!, actionID: "clipboard", side: .left),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000007")!, actionID: "agents", side: .left),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000003")!, actionID: "settings", side: .right),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000004")!, actionID: "mixer", side: .right),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000005")!, actionID: "commands", side: .bottom),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000006")!, actionID: "keepawake", side: .bottom),
    ])

    public func buttons(on side: HomeButtonSide) -> [HomeButton] { buttons.filter { $0.side == side } }

    public func hasRoom(on side: HomeButtonSide) -> Bool { buttons(on: side).count < Self.maxPerSide }

    public func contains(actionID: String) -> Bool { buttons.contains { $0.actionID == actionID } }

    /// The first side with room, left to right to bottom.
    public var firstFreeSide: HomeButtonSide? { HomeButtonSide.allCases.first(where: hasRoom) }

    /// Adds a button for a known action nobody shows yet. False when refused (unknown, already there, side full).
    @discardableResult
    public mutating func add(actionID: String, side: HomeButtonSide? = nil) -> Bool {
        guard let resolved = HomeActionCatalog.resolve(actionID), !contains(actionID: resolved),
              let target = side ?? firstFreeSide, hasRoom(on: target) else { return false }
        buttons.append(HomeButton(actionID: resolved, side: target))
        return true
    }

    /// Offers the Claude shortcut to a layout that does not have it: left first, then right, then the bottom row.
    /// A layout with no room left stays as it is.
    public func addingClaudeShortcut() -> HomeButtonLayout {
        var copy = self
        for side in [HomeButtonSide.left, .right, .bottom] where copy.hasRoom(on: side) {
            if copy.add(actionID: HomeClaude.actionID, side: side) { break }
        }
        return copy
    }

    public mutating func remove(id: UUID) { buttons.removeAll { $0.id == id } }

    /// Moves a button to another side (appended last there). False when that side is full.
    @discardableResult
    public mutating func move(id: UUID, to side: HomeButtonSide) -> Bool {
        guard let index = buttons.firstIndex(where: { $0.id == id }) else { return false }
        if buttons[index].side == side { return true }
        guard hasRoom(on: side) else { return false }
        var button = buttons.remove(at: index)
        button.side = side
        buttons.append(button)
        return true
    }

    /// Swaps a button with its neighbour on the same side (-1 earlier, +1 later). False at the end of the row.
    @discardableResult
    public mutating func reorder(id: UUID, by offset: Int) -> Bool {
        guard let button = buttons.first(where: { $0.id == id }) else { return false }
        let row = buttons(on: button.side)
        guard let at = row.firstIndex(where: { $0.id == id }), row.indices.contains(at + offset) else { return false }
        let neighbour = row[at + offset].id
        guard let i = buttons.firstIndex(where: { $0.id == id }),
              let j = buttons.firstIndex(where: { $0.id == neighbour }) else { return false }
        buttons.swapAt(i, j)
        return true
    }

    /// Known actions only (aliases mapped), no repeated action or id, at most three per side.
    public func sanitized() -> HomeButtonLayout {
        var seenActions = Set<String>(), seenIDs = Set<UUID>()
        var perSide: [HomeButtonSide: Int] = [:]
        var kept: [HomeButton] = []
        for var button in buttons {
            guard let action = HomeActionCatalog.resolve(button.actionID),
                  seenActions.insert(action).inserted, seenIDs.insert(button.id).inserted,
                  perSide[button.side, default: 0] < Self.maxPerSide else { continue }
            button.actionID = action
            perSide[button.side, default: 0] += 1
            kept.append(button)
        }
        return HomeButtonLayout(buttons: kept)
    }

    // MARK: - Persistence

    private struct Envelope: Codable {
        var version: Int
        var buttons: [HomeButton]
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(Envelope(version: Self.version, buttons: buttons))
    }

    /// Nothing stored, a damaged blob or a newer version gives the defaults. A stored empty list stays empty:
    /// the user may want no round button at all.
    public static func decode(_ data: Data?) -> HomeButtonLayout {
        guard let data, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version <= version else { return initial }
        let clean = HomeButtonLayout(buttons: envelope.buttons).sanitized()
        // Every id unknown (a layout from another build): the defaults beat an empty island.
        return clean.buttons.isEmpty && !envelope.buttons.isEmpty ? initial : clean
    }
}
