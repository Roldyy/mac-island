import Foundation

/// Which device to select, as a pure function. `nil` means leave the default alone.
enum DevicePriorityResolver {
    /// - `available`: UIDs of the devices that exist right now for this direction.
    /// - `priority`: the user's ordered list, best first; a UID listed twice counts at its first place.
    /// - `lastManualChange` / `grace`: a default the user picked by hand less than `grace` seconds ago is
    ///   kept, unless it is no longer available.
    static func resolve(available: [String], priority: [String], current: String?,
                        lastManualChange: Date? = nil, now: Date = Date(),
                        grace: TimeInterval = 0) -> String? {
        let present = Set(available)
        guard let best = priority.first(where: { present.contains($0) }) else { return nil }
        if best == current { return nil }
        if let current, present.contains(current), let lastManualChange,
           now.timeIntervalSince(lastManualChange) < grace {
            return nil
        }
        return best
    }
}
