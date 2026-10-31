import Foundation
import IslandUI

/// What the two wings of the closed island show right now.
public struct ClosedIslandContent: Equatable, Sendable {
    public var leading: [AmbientIndicator]
    public var trailing: [AmbientIndicator]
    /// Edge dot for an alert the arbiter found no wing for.
    public var dot: IslandStatus?
    /// Rotation pages: above 1 when at least one wing has more indicators than room.
    public var pageCount: Int
    /// The page shown, `0..<pageCount`.
    public var step: Int

    public static let empty = ClosedIslandContent(leading: [], trailing: [], dot: nil, pageCount: 1, step: 0)

    public init(leading: [AmbientIndicator], trailing: [AmbientIndicator], dot: IslandStatus? = nil,
                pageCount: Int = 1, step: Int = 0) {
        self.leading = leading
        self.trailing = trailing
        self.dot = dot
        self.pageCount = max(pageCount, 1)
        self.step = step
    }

    public var isEmpty: Bool { leading.isEmpty && trailing.isEmpty && dot == nil }
    public var all: [AmbientIndicator] { leading + trailing }
    public var isRotating: Bool { pageCount > 1 }
    /// The step after this one; 0 when nothing rotates.
    public var nextStep: Int { isRotating ? (step + 1) % pageCount : 0 }
}

/// Pure: from the indicators that exist and the user's settings, what each wing shows and which rotation
/// step comes next. Same input in any order gives the same output.
///
/// 1. Disabled channels are dropped. The rest is ranked by priority, then the user's order, then id.
/// 2. Pinned indicators (urgent, or Claude working / waiting, or an alert) take their wing first and never rotate.
/// 3. The others share what room is left. A wing with more than fits cycles through pages, one page per step.
/// 4. A wing holds at most `maxPerWing` (1 or 2) indicators.
public enum ClosedIslandLayout {
    public static func rank(_ a: AmbientIndicator, _ b: AmbientIndicator, settings: ClosedIslandSettings) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        let ia = settings.orderIndex(a.channel), ib = settings.orderIndex(b.channel)
        if ia != ib { return ia < ib }
        return a.id < b.id
    }

    public static func resolve(_ indicators: [AmbientIndicator], settings: ClosedIslandSettings, step: Int = 0) -> ClosedIslandContent {
        let perWing = min(max(settings.maxPerWing, ClosedIslandSettings.perWingRange.lowerBound), ClosedIslandSettings.perWingRange.upperBound)
        var seen = Set<String>()
        let ranked = indicators
            .filter { settings.isEnabled($0.channel) }
            .sorted { rank($0, $1, settings: settings) }
            .filter { seen.insert($0.id).inserted }

        var pinned: (leading: [AmbientIndicator], trailing: [AmbientIndicator]) = ([], [])
        for item in ranked where item.isPinned {
            switch target(for: item, leading: pinned.leading.count, trailing: pinned.trailing.count, room: perWing) {
            case .leading: pinned.leading.append(item)
            case .trailing: pinned.trailing.append(item)
            case nil: break  // more urgent items than room: the lowest ranked wait
            }
        }

        let leadRoom = perWing - pinned.leading.count, trailRoom = perWing - pinned.trailing.count
        var flowing: (leading: [AmbientIndicator], trailing: [AmbientIndicator]) = ([], [])
        for item in ranked where !item.isPinned {
            // A wing the pinned items filled takes nothing. Otherwise unlimited room: pages decide what is
            // shown. Balance by what each wing already holds.
            let side: AmbientWing
            if leadRoom <= 0 { side = .trailing } else if trailRoom <= 0 { side = .leading } else {
                side = target(for: item, leading: pinned.leading.count + flowing.leading.count,
                              trailing: pinned.trailing.count + flowing.trailing.count, room: .max) ?? .leading
            }
            if side == .leading { flowing.leading.append(item) } else { flowing.trailing.append(item) }
        }

        let leadPages = pageCount(flowing.leading.count, room: leadRoom)
        let trailPages = pageCount(flowing.trailing.count, room: trailRoom)
        let pages = settings.rotates ? max(leadPages, trailPages, 1) : 1
        let current = pages > 1 ? ((step % pages) + pages) % pages : 0

        return ClosedIslandContent(
            leading: pinned.leading + page(flowing.leading, room: leadRoom, pages: leadPages, step: settings.rotates ? current : 0),
            trailing: pinned.trailing + page(flowing.trailing, room: trailRoom, pages: trailPages, step: settings.rotates ? current : 0),
            pageCount: pages, step: current)
    }

    /// The wing an item goes to: its preference when there is room, else the other one, else nowhere.
    /// Without a preference, the emptier wing (leading on a tie).
    private static func target(for item: AmbientIndicator, leading: Int, trailing: Int, room: Int) -> AmbientWing? {
        let order: [AmbientWing]
        switch item.wing {
        case .leading?: order = [.leading, .trailing]
        case .trailing?: order = [.trailing, .leading]
        case nil: order = leading <= trailing ? [.leading, .trailing] : [.trailing, .leading]
        }
        return order.first { ($0 == .leading ? leading : trailing) < room }
    }

    private static func pageCount(_ count: Int, room: Int) -> Int {
        guard room > 0, count > room else { return 1 }
        return (count + room - 1) / room
    }

    private static func page(_ items: [AmbientIndicator], room: Int, pages: Int, step: Int) -> [AmbientIndicator] {
        guard room > 0, !items.isEmpty else { return [] }
        guard pages > 1 else { return Array(items.prefix(room)) }
        let start = (step % pages) * room
        return Array(items[start..<min(start + room, items.count)])
    }
}
