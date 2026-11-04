import Foundation

/// The status chips the user wants on the open island, in order. Pure value: enable, disable and reorder are all here,
/// so the row, the Settings page and the tests share one set of rules (same shape as `ExtraDockLayout`).
///
/// Stored as `{"version":1,"ids":["network","load",...]}` under one defaults key. A newer version or a damaged value
/// gives the defaults; a stored empty list stays empty (the user may want no chip). An id this build does not know
/// (a kind added by a later version) is dropped on read.
public struct StatusChipLayout: Codable, Equatable, Sendable {
    public static let version = 1

    /// Enabled kinds, in display order. Each kind appears once.
    public var kinds: [StatusChipKind]

    public init(kinds: [StatusChipKind]) { self.kinds = kinds }

    /// A sensible start: network, load, next appointment.
    public static let initial = StatusChipLayout(kinds: [.network, .load, .nextEvent])

    public func contains(_ kind: StatusChipKind) -> Bool { kinds.contains(kind) }

    /// Kinds that are off, in catalog order.
    public var disabledKinds: [StatusChipKind] { StatusChipKind.allCases.filter { !contains($0) } }

    /// Appends a kind. False when it is already there.
    @discardableResult
    public mutating func enable(_ kind: StatusChipKind) -> Bool {
        guard !contains(kind) else { return false }
        kinds.append(kind)
        return true
    }

    public mutating func disable(_ kind: StatusChipKind) { kinds.removeAll { $0 == kind } }

    public mutating func setEnabled(_ kind: StatusChipKind, _ on: Bool) {
        if on { enable(kind) } else { disable(kind) }
    }

    /// Moves `kind` so it sits just before `target`, or last when `target` is nil. False when either is not enabled.
    @discardableResult
    public mutating func move(_ kind: StatusChipKind, before target: StatusChipKind?) -> Bool {
        guard let from = kinds.firstIndex(of: kind) else { return false }
        if let target {
            guard target != kind, kinds.contains(target) else { return target == kind }
            kinds.remove(at: from)
            kinds.insert(kind, at: kinds.firstIndex(of: target) ?? kinds.endIndex)
        } else {
            kinds.append(kinds.remove(at: from))
        }
        return true
    }

    /// Swaps with the neighbour (-1 earlier, +1 later). False at either end.
    @discardableResult
    public mutating func reorder(_ kind: StatusChipKind, by offset: Int) -> Bool {
        guard let at = kinds.firstIndex(of: kind), kinds.indices.contains(at + offset) else { return false }
        kinds.swapAt(at, at + offset)
        return true
    }

    /// Each kind once, first occurrence kept.
    public func sanitized() -> StatusChipLayout {
        var seen = Set<StatusChipKind>()
        return StatusChipLayout(kinds: kinds.filter { seen.insert($0).inserted })
    }

    // MARK: - Drag and drop

    private static let dragPrefix = "mis.statuschip:"

    /// What a dragged row carries. The prefix makes the list refuse any other text dropped on it.
    public static func dragPayload(_ kind: StatusChipKind) -> String { dragPrefix + kind.rawValue }

    public static func dragKind(from payload: String) -> StatusChipKind? {
        guard payload.hasPrefix(dragPrefix) else { return nil }
        return StatusChipKind(rawValue: String(payload.dropFirst(dragPrefix.count)))
    }

    // MARK: - Persistence

    private struct Envelope: Codable {
        var version: Int
        var ids: [String]
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(Envelope(version: Self.version, ids: kinds.map(\.rawValue)))
    }

    /// Nothing stored, a damaged blob or a newer version gives the defaults.
    public static func decode(_ data: Data?) -> StatusChipLayout {
        guard let data, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version <= version else { return initial }
        return StatusChipLayout(kinds: envelope.ids.compactMap(StatusChipKind.init(rawValue:))).sanitized()
    }
}
