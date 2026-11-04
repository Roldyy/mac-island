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

/// The user's round buttons: at most eight per side and six at the bottom, no action twice, order = order in `buttons`.
/// Stored as `{"version":1,"buttons":[{"id","actionID","side","label"}]}` under the island layout key. The shape did
/// not change when the caps rose (a 3-per-side layout is a valid layout), so the version stays 1 and an older build
/// still reads what a newer one wrote. `actionID` is a `HomeActionCatalog` id ("terminal") or, for every other command
/// of the app, the id `ShellContext.dockCatalog()` gives it ("port.ocr", "feature.fans"): see `HomeActionCatalog.stored`.
public struct HomeButtonLayout: Codable, Equatable, Sendable {
    public static let version = 1
    public static let maxPerSide = 8
    public static let maxBottom = 6

    /// Most buttons a side holds: eight on each side column, six on the bottom row.
    public static func capacity(of side: HomeButtonSide) -> Int { side == .bottom ? maxBottom : maxPerSide }

    public var buttons: [HomeButton]

    public init(buttons: [HomeButton]) { self.buttons = buttons }

    /// Left: Terminal, Presse-papiers, Claude. Right: Réglages, Mélangeur. Bottom: Commandes, Garder éveillé.
    public static let initial = HomeButtonLayout(buttons: [
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000001")!, actionID: "terminal", side: .left),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000002")!, actionID: "clipboard", side: .left),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000007")!, actionID: "agents", side: .left),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000003")!, actionID: "settings", side: .right),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000004")!, actionID: "mixer", side: .right),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000005")!, actionID: "commands", side: .bottom),
        HomeButton(id: UUID(uuidString: "6D0A0001-0000-4000-8000-000000000006")!, actionID: "keepawake", side: .bottom),
    ])

    public func buttons(on side: HomeButtonSide) -> [HomeButton] { buttons.filter { $0.side == side } }

    public func hasRoom(on side: HomeButtonSide) -> Bool { buttons(on: side).count < Self.capacity(of: side) }

    /// Whether the action is already shown, whichever id form (legacy or dock-catalog) either side uses.
    public func contains(actionID: String) -> Bool {
        guard let identity = HomeActionCatalog.identity(of: actionID) else { return false }
        return buttons.contains { HomeActionCatalog.identity(of: $0.actionID) == identity }
    }

    /// The first side with room, left to right to bottom.
    public var firstFreeSide: HomeButtonSide? { HomeButtonSide.allCases.first(where: hasRoom) }

    /// Adds a button for an action nobody shows yet: a home action or any command of the dock catalog. False when
    /// refused (unknown, already there, side full).
    @discardableResult
    public mutating func add(actionID: String, side: HomeButtonSide? = nil) -> Bool {
        guard let resolved = HomeActionCatalog.stored(actionID), !contains(actionID: resolved),
              let target = side ?? firstFreeSide, hasRoom(on: target) else { return false }
        buttons.append(HomeButton(actionID: resolved, side: target))
        return true
    }

    /// The Explorer button is redundant now that the Home grid lists every shortcut: a layout saved with it gets a
    /// Terminal button in its place (same side and position), or simply loses it when Terminal is already there.
    public func replacingExplorerWithTerminal() -> HomeButtonLayout {
        var copy = self
        guard let at = copy.buttons.firstIndex(where: { $0.actionID == "explore" }) else { return self }
        if copy.contains(actionID: "terminal") {
            copy.buttons.remove(at: at)
        } else {
            copy.buttons[at].actionID = "terminal"
        }
        return copy
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

    /// Known actions only (aliases mapped, a dock-catalog id kept in its stored form), no repeated action or id, at
    /// most `capacity(of:)` per side.
    public func sanitized() -> HomeButtonLayout {
        var seenActions = Set<String>(), seenIDs = Set<UUID>()
        var perSide: [HomeButtonSide: Int] = [:]
        var kept: [HomeButton] = []
        for var button in buttons {
            guard let action = HomeActionCatalog.stored(button.actionID),
                  let identity = HomeActionCatalog.identity(of: action),
                  seenActions.insert(identity).inserted, seenIDs.insert(button.id).inserted,
                  perSide[button.side, default: 0] < Self.capacity(of: button.side) else { continue }
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
