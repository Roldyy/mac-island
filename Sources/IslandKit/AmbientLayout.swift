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
    /// The clock in the fixed center slot of a pill without a notch (nil with a hardware notch, where the clock
    /// is the first item of the leading wing, and nil while the clock is off). Never rotates.
    public var center: AmbientIndicator?

    public static let empty = ClosedIslandContent(leading: [], trailing: [], dot: nil, pageCount: 1, step: 0)

    public init(leading: [AmbientIndicator], trailing: [AmbientIndicator], dot: IslandStatus? = nil,
                pageCount: Int = 1, step: Int = 0, center: AmbientIndicator? = nil) {
        self.leading = leading
        self.trailing = trailing
        self.dot = dot
        self.pageCount = max(pageCount, 1)
        self.step = step
        self.center = center
    }

    public var isEmpty: Bool { leading.isEmpty && trailing.isEmpty && dot == nil && center == nil }
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
        // The default order is the wing table's (Claude, then music, then the network; the battery, then the
        // system...), whatever the priority: priority pins an item, it does not reorder a wing. An order the user
        // changed in Settings goes by priority first, then by that order.
        if settings.order == AmbientChannel.userChoices {
            let ta = AmbientWingTable.rank(a.channel), tb = AmbientWingTable.rank(b.channel)
            if ta != tb { return ta < tb }
            if a.priority != b.priority { return a.priority > b.priority }
        } else {
            if a.priority != b.priority { return a.priority > b.priority }
            let ia = settings.orderIndex(a.channel), ib = settings.orderIndex(b.channel)
            if ia != ib { return ia < ib }
        }
        return a.id < b.id
    }

    /// The wing of an indicator: the table's, or the indicator's own preference for an alert.
    static func side(_ item: AmbientIndicator) -> AmbientWing? { AmbientWingTable.wing(for: item.channel) ?? item.wing }

    /// `centered`: a screen without a notch. The clock then takes the fixed center slot and the wings keep their
    /// full room; with a notch the clock is the first item of the leading wing and counts against its room.
    public static func resolve(_ indicators: [AmbientIndicator], settings: ClosedIslandSettings, step: Int = 0,
                               centered: Bool = false) -> ClosedIslandContent {
        let perWing = min(max(settings.maxPerWing, ClosedIslandSettings.perWingRange.lowerBound), ClosedIslandSettings.perWingRange.upperBound)
        var seen = Set<String>()
        var ranked = indicators
            .filter { settings.isEnabled($0.channel) && $0.isReadable }
            .sorted { rank($0, $1, settings: settings) }
            .filter { seen.insert($0.id).inserted }
        let clock = ranked.first { $0.channel == AmbientChannel.clock }
        ranked.removeAll { $0.channel == AmbientChannel.clock }

        var pinned: (leading: [AmbientIndicator], trailing: [AmbientIndicator]) = ([], [])
        // With a hardware notch the clock takes the innermost slot of the left wing (after the pinned Claude item).
        let clockSlot = (clock != nil && !centered) ? 1 : 0
        // Pinned items of a fixed wing (Claude waiting, a low battery) take their side first; an alert, which has
        // no side of its own, then takes whichever side still has room.
        let pinnedItems = ranked.filter { $0.isPinned }
        for item in pinnedItems.filter({ side($0) != nil && AmbientWingTable.wing(for: $0.channel) != nil })
            + pinnedItems.filter({ AmbientWingTable.wing(for: $0.channel) == nil }) {
            switch target(for: item, leading: pinned.leading.count + clockSlot, trailing: pinned.trailing.count, room: perWing) {
            case .leading: pinned.leading.append(item)
            case .trailing: pinned.trailing.append(item)
            case nil: break  // more urgent items than room: the lowest ranked wait
            }
        }

        let leadRoom = perWing - pinned.leading.count - clockSlot, trailRoom = perWing - pinned.trailing.count
        var flowing: (leading: [AmbientIndicator], trailing: [AmbientIndicator]) = ([], [])
        for item in ranked where !item.isPinned {
            // A wing the pinned items filled takes nothing. Otherwise unlimited room: pages decide what is
            // shown. Balance by what each wing already holds.
            let side: AmbientWing
            if leadRoom <= 0 { side = .trailing } else if trailRoom <= 0 { side = .leading } else {
                side = target(for: item, leading: pinned.leading.count + clockSlot + flowing.leading.count,
                              trailing: pinned.trailing.count + flowing.trailing.count, room: .max) ?? .leading
            }
            if side == .leading { flowing.leading.append(item) } else { flowing.trailing.append(item) }
        }

        let leadPages = pageCount(flowing.leading.count, room: leadRoom)
        let trailPages = pageCount(flowing.trailing.count, room: trailRoom)
        let pages = settings.rotates ? max(leadPages, trailPages, 1) : 1
        let current = pages > 1 ? ((step % pages) + pages) % pages : 0

        var leading = pinned.leading + page(flowing.leading, room: leadRoom, pages: leadPages, step: settings.rotates ? current : 0)
        // With a hardware notch the clock is the innermost item of the left wing, right beside the notch.
        if var inner = clock, !centered {
            inner.detail = nil
            leading.append(inner)
        }
        let trailing = pinned.trailing + page(flowing.trailing, room: trailRoom, pages: trailPages, step: settings.rotates ? current : 0)
        var center: AmbientIndicator?
        if centered, var shown = clock {
            // The date only shows while the wings are empty: that is when the pill has room for it.
            if !leading.isEmpty || !trailing.isEmpty { shown.detail = nil }
            center = shown
        }
        return ClosedIslandContent(leading: leading, trailing: trailing, pageCount: pages, step: current, center: center)
    }

    /// The wing an item goes to: its preference when there is room, else the other one, else nowhere.
    /// Without a preference, the emptier wing (leading on a tie).
    private static func target(for item: AmbientIndicator, leading: Int, trailing: Int, room: Int) -> AmbientWing? {
        let order: [AmbientWing]
        switch side(item) {
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
