import Foundation
import Observation

/// Keeps `sessions` current and mirrors them into the activity sink.
///
/// Polls every 2 s instead of watching the directory: a DispatchSource on a directory fires on added or
/// removed entries, not when Claude Code rewrites a file in place (which is how status changes), so it
/// would need one watcher per file. A readdir plus a few files of at most 16 KB every 2 s is cheaper
/// than that bookkeeping. The reads run off the main actor.
@MainActor
@Observable
public final class ClaudeLiveMonitor {
    public private(set) var sessions: [ClaudeSession] = []

    @ObservationIgnored private let snapshot: @Sendable () -> [ClaudeSession]
    @ObservationIgnored private let sink: (any ClaudeActivitySink)?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var posted: Set<String> = []
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(source: ClaudeLiveSource, sink: (any ClaudeActivitySink)? = nil, interval: Duration = .seconds(2)) {
        self.snapshot = { source.snapshot() }
        self.sink = sink
        self.interval = interval
    }

    /// Test seam: any snapshot function.
    public init(snapshot: @escaping @Sendable () -> [ClaudeSession], sink: (any ClaudeActivitySink)? = nil,
                interval: Duration = .seconds(2)) {
        self.snapshot = snapshot
        self.sink = sink
        self.interval = interval
    }

    public func start() {
        guard loop == nil else { return }
        let read = snapshot
        loop = Task { [weak self, interval] in
            while !Task.isCancelled {
                let fresh = await Task.detached(priority: .utility) { read() }.value
                guard let self else { return }
                self.apply(fresh)
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        apply([])
    }

    /// One synchronous pass (also what the tests drive).
    public func refresh() { apply(snapshot()) }

    func apply(_ fresh: [ClaudeSession]) {
        if fresh != sessions { sessions = fresh }
        guard let sink else { return }
        var wanted: Set<String> = []
        for session in fresh {
            guard let activity = ClaudeActivityMapper.activity(for: session) else { continue }
            wanted.insert(activity.id)
            sink.post(activity)
        }
        for id in posted.subtracting(wanted) { sink.withdraw(id: id) }
        posted = wanted
    }
}
