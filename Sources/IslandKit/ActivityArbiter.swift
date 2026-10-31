import IslandUI

/// Decides what the closed island draws. Pure: same activities in any order give the same layout.
public enum ActivityArbiter {
    /// Priority desc, then id asc, so a tie never depends on arrival order.
    static func ranked(_ activities: [IslandActivity]) -> [IslandActivity] {
        activities.sorted { a, b in
            a.priority != b.priority ? a.priority > b.priority : a.id < b.id
        }
    }

    /// Order for the dot only; `IslandStatus` has no ordering of its own.
    static func severity(_ status: IslandStatus) -> Int {
        switch status {
        case .neutral: 0
        case .success: 1
        case .info: 2
        case .warning: 3
        case .danger: 4
        @unknown default: 2
        }
    }

    /// Each wing takes the best-ranked activity that has an item for it. An activity that asks for a
    /// dot and lost (or never had) a wing falls back to the edge dot; the dot shows the worst status.
    public static func resolve(_ activities: [IslandActivity]) -> ActivityLayout {
        var layout = ActivityLayout.empty
        var seen = Set<String>()
        for activity in ranked(activities) where seen.insert(activity.id).inserted {
            var dropped = activity.leading == nil && activity.trailing == nil
            if let item = activity.leading {
                if layout.leading == nil { layout.leading = item } else { dropped = true }
            }
            if let item = activity.trailing {
                if layout.trailing == nil { layout.trailing = item } else { dropped = true }
            }
            guard activity.showsDot, dropped else { continue }
            let statuses = [activity.leading?.status, activity.trailing?.status].compactMap { $0 }
            let status = statuses.max { severity($0) < severity($1) } ?? .neutral
            if layout.dot.map({ severity($0) < severity(status) }) ?? true { layout.dot = status }
        }
        return layout
    }
}
