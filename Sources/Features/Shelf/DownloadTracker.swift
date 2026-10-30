import Foundation

/// Decides whether a file is finished writing. Pure: the clock is passed in.
/// Finished = modified at least `settle` seconds ago AND its size did not change in the last
/// `settle` seconds of observation. A modification date in the future (clock skew, copied files)
/// says nothing about age, so only the size stability counts then, measured from first sight.
struct DownloadTracker {
    private struct Observation { var size: Int64; var changedAt: Date?; let firstSeen: Date }

    let settle: TimeInterval
    private var seen: [String: Observation] = [:]
    var observedCount: Int { seen.count }

    init(settle: TimeInterval = 2) { self.settle = settle }

    mutating func isFinished(path: String, size: Int64, modified: Date, now: Date) -> Bool {
        var obs = seen[path] ?? Observation(size: size, changedAt: nil, firstSeen: now)
        if obs.size != size {
            obs.size = size
            obs.changedAt = now
        }
        seen[path] = obs
        let age = now.timeIntervalSince(modified)
        if age >= 0 {
            if age < settle { return false }
        } else if now.timeIntervalSince(obs.changedAt ?? obs.firstSeen) < settle {
            return false
        }
        if let changed = obs.changedAt, now.timeIntervalSince(changed) < settle { return false }
        return true
    }

    mutating func retain(only paths: Set<String>) {
        seen = seen.filter { paths.contains($0.key) }
    }
}
