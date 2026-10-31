import Foundation

/// Card order, visibility and the two-per-row packing. Pure.
enum AgentsCardLayout {
    /// Stored ids (an array, or one comma-separated string) in order, unknown and repeated ids dropped.
    static func ids(from raw: Any?) -> [String] {
        let list: [String]
        if let array = raw as? [String] { list = array }
        else if let text = raw as? String { list = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        else { list = [] }
        var seen: Set<String> = []
        return list.filter { AgentsCard(rawValue: $0) != nil && seen.insert($0).inserted }
    }

    /// The saved order first, then every card the saved list does not know, in default order.
    static func order(from raw: Any?) -> [AgentsCard] {
        let saved = ids(from: raw).compactMap(AgentsCard.init(rawValue:))
        return saved + AgentsCard.allCases.filter { !saved.contains($0) }
    }

    static func hidden(from raw: Any?) -> Set<AgentsCard> {
        Set(ids(from: raw).compactMap(AgentsCard.init(rawValue:)))
    }

    /// What the page draws: ordered, not hidden, and without "Réinitialisations" when no Codex data exists.
    static func visible(order: [AgentsCard], hidden: Set<AgentsCard>, hasCodexData: Bool) -> [AgentsCard] {
        order.filter { !hidden.contains($0) && ($0 != .resets || hasCodexData) }
    }

    /// Full-width cards sit alone; half-width cards pair up in order. A half-width card left over before a
    /// full-width one (or at the end) takes the whole row.
    /// Below `pairingWidth` (the real island page is 540 pt of content) every card takes a whole row.
    static let pairingWidth: CGFloat = 760

    static func rows(_ cards: [AgentsCard], width: CGFloat) -> [[AgentsCard]] {
        width >= pairingWidth ? rows(cards) : cards.map { [$0] }
    }

    static func rows(_ cards: [AgentsCard]) -> [[AgentsCard]] {
        var rows: [[AgentsCard]] = []
        var pending: AgentsCard?
        for card in cards {
            if card.isFullWidth {
                if let waiting = pending { rows.append([waiting]); pending = nil }
                rows.append([card])
            } else if let waiting = pending {
                rows.append([waiting, card])
                pending = nil
            } else {
                pending = card
            }
        }
        if let waiting = pending { rows.append([waiting]) }
        return rows
    }

    /// `move` clamps at the ends.
    static func moved(_ card: AgentsCard, by offset: Int, in order: [AgentsCard]) -> [AgentsCard] {
        guard let index = order.firstIndex(of: card) else { return order }
        let target = min(max(index + offset, 0), order.count - 1)
        guard target != index else { return order }
        var next = order
        next.remove(at: index)
        next.insert(card, at: target)
        return next
    }
}
