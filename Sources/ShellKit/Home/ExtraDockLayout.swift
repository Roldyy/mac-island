import Foundation

/// The commands of the extra dock, in order. Pure value: add, remove, reorder and the stored form are all here, so
/// the view and the Settings editor share one set of rules and the tests need no UI.
///
/// Stored as `{"version":1,"ids":["tab.agents", ...]}` under one defaults key. Version 0 was a bare JSON array of
/// ids (short names such as `keepawake`); it is read and rewritten as version 1. A newer version or a damaged value
/// gives the defaults; a stored empty list stays empty (the user may want an empty dock).
public struct ExtraDockLayout: Codable, Equatable, Sendable {
    public static let version = 1
    public static let maxItems = 16

    public var ids: [String]

    public init(ids: [String]) { self.ids = ids }

    /// A sensible start: Claude, Terminal, Presse-papiers, Garder éveillé, Capture, Commandes.
    public static let initial = ExtraDockLayout(ids: [
        "tab.agents", "tab.terminal", "tab.clipboard", "quick.keepawake", "quick.capture", "quick.commands",
    ])

    public var isFull: Bool { ids.count >= Self.maxItems }
    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Appends a command. False when it is already there, the id is empty or the dock is full.
    @discardableResult
    public mutating func add(_ id: String) -> Bool {
        guard !id.isEmpty, !contains(id), !isFull else { return false }
        ids.append(id)
        return true
    }

    public mutating func remove(_ id: String) { ids.removeAll { $0 == id } }

    /// Moves `id` so it sits just before `target`, or last when `target` is nil. False when either is unknown.
    @discardableResult
    public mutating func move(_ id: String, before target: String?) -> Bool {
        guard let from = ids.firstIndex(of: id) else { return false }
        if let target {
            guard target != id, ids.contains(target) else { return target == id }
            ids.remove(at: from)
            ids.insert(id, at: ids.firstIndex(of: target) ?? ids.endIndex)
        } else {
            ids.append(ids.remove(at: from))
        }
        return true
    }

    /// Swaps with the neighbour (-1 earlier, +1 later). False at either end.
    @discardableResult
    public mutating func reorder(_ id: String, by offset: Int) -> Bool {
        guard let at = ids.firstIndex(of: id), ids.indices.contains(at + offset) else { return false }
        ids.swapAt(at, at + offset)
        return true
    }

    /// No empty id, no repeat, at most `maxItems`. Unknown ids stay: a command registered later by the app (or a
    /// panel that exists only on another build) must not be lost by a read.
    public func sanitized() -> ExtraDockLayout {
        var seen = Set<String>()
        let kept = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        return ExtraDockLayout(ids: Array(kept.prefix(Self.maxItems)))
    }

    // MARK: - Drag and drop

    private static let dragPrefix = "mis.extradock:"

    /// What a dragged button carries. The prefix makes the dock refuse any other text dropped on it.
    public static func dragPayload(_ id: String) -> String { dragPrefix + id }

    public static func dragID(from payload: String) -> String? {
        payload.hasPrefix(dragPrefix) && payload.count > dragPrefix.count ? String(payload.dropFirst(dragPrefix.count)) : nil
    }

    // MARK: - Persistence

    private struct Envelope: Codable {
        var version: Int
        var ids: [String]
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(Envelope(version: Self.version, ids: ids))
    }

    /// Short ids of version 0 and their current names.
    static let legacyIDs: [String: String] = [
        "keepawake": "quick.keepawake", "capture": "quick.capture", "commands": "quick.commands",
        "lockScreen": "quick.lockScreen", "cleaning": "quick.cleaning", "settings": "nav.settings",
        "explore": "nav.explore", "terminal": "tab.terminal", "agents": "tab.agents", "clipboard": "tab.clipboard",
        "shelf": "tab.shelf", "nowplaying": "tab.nowplaying", "monitor": "tab.monitor", "fans": "tab.fans",
        "mixer": "tab.audio",
    ]

    /// Nothing stored, a damaged blob or a newer version gives the defaults.
    public static func decode(_ data: Data?) -> ExtraDockLayout {
        guard let data else { return initial }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            guard envelope.version <= version else { return initial }
            return ExtraDockLayout(ids: envelope.ids).sanitized()
        }
        // Version 0: a bare array of short ids.
        if let legacy = try? JSONDecoder().decode([String].self, from: data) {
            return ExtraDockLayout(ids: legacy.map { legacyIDs[$0] ?? $0 }).sanitized()
        }
        return initial
    }
}
