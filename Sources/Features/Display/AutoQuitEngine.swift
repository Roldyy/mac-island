import Foundation

struct PendingQuit: Equatable, Identifiable {
    var pid: Int32
    var bundleID: String?
    var name: String
    var deadline: Date
    var id: Int32 { pid }
}

/// Planner plus the announce-then-act countdown. Pure: the caller supplies time and snapshots
/// and performs the terminations it is told about.
struct AutoQuitEngine {
    struct Output: Equatable {
        var pending: [PendingQuit] = []
        var terminate: [Int32] = []
    }

    var countdown: TimeInterval = 60
    private var tracker = IdleTracker()
    private var monitoringSince: Date?
    private var pending: [Int32: PendingQuit] = [:]
    private var attempted: Set<Int32> = []

    init(countdown: TimeInterval = 60) { self.countdown = countdown }

    mutating func reset() {
        tracker.reset()
        monitoringSince = nil
        pending = [:]
        attempted = []
    }

    mutating func tick(apps: [AppSnapshot], now: Date, config: AutoQuitConfig,
                       enabled: Bool, dryRun: Bool) -> Output {
        guard enabled else {
            reset()
            return Output()
        }
        if monitoringSince == nil { monitoringSince = now }
        tracker.update(apps, now: now)
        attempted.formIntersection(Set(apps.map(\.pid)))

        let candidates = AutoQuitPlanner.candidates(
            apps: apps, lastActive: tracker.lastActive, now: now,
            monitoringSince: monitoringSince ?? now, config: config
        ).filter { !attempted.contains($0.pid) }

        var next: [Int32: PendingQuit] = [:]
        for app in candidates {
            next[app.pid] = pending[app.pid] ?? PendingQuit(
                pid: app.pid, bundleID: app.bundleID, name: app.name,
                deadline: now.addingTimeInterval(countdown))
        }
        pending = next

        var output = Output()
        if !dryRun {
            let due = next.values.filter { $0.deadline <= now }.map(\.pid).sorted()
            for pid in due {
                pending[pid] = nil
                attempted.insert(pid)
            }
            output.terminate = due
        }
        output.pending = pending.values.sorted { $0.pid < $1.pid }
        return output
    }
}
