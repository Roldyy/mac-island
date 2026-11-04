import Foundation
import Observation

/// When the monitor looks, apart from file events.
public struct ClaudeLiveCadence: Sendable {
    /// First event of a burst to the read: later events of the same burst join it (a window, not a reset,
    /// so a file rewritten every second still gets read).
    public var debounce: Duration = .milliseconds(250)
    /// Safety poll while a session exists: catches a process that died without touching its file.
    public var slowWithSessions: Duration = .seconds(30)
    /// Safety poll with no session: only re-arms the watchers and checks the folder.
    public var slowIdle: Duration = .seconds(120)
    public init() {}
}

/// The one source of Claude Code sessions for the whole app: the Agents tab, the closed island's activity
/// and the usage warm-up all read `ClaudeLiveMonitor.shared`, none of them reads the session files itself.
///
/// Event driven: file-system events on `~/.claude/sessions` (and each session file, rewritten in place) and
/// on the hook folder wake one debounced read. A slow poll (30 s with a session, 120 s without) catches a
/// pid that died silently and re-arms a folder that did not exist yet. With no session file the poll reads
/// nothing. It runs only while a consumer holds it (`acquire`); the last `release` stops everything.
/// Reads run off the main actor; every security rule stays in `ClaudeSessionReader` and `ClaudeHookStore`.
@MainActor
@Observable
public final class ClaudeLiveMonitor {
    /// Built lazily on first use. The app sets `sink` once at launch; tests build their own monitors.
    public static let shared = ClaudeLiveMonitor(
        source: ClaudeLiveSource(reader: ClaudeSessionReader(directory: ClaudeSessionReader.defaultDirectory)))

    public private(set) var sessions: [ClaudeSession] = []

    @ObservationIgnored public var sink: (any ClaudeActivitySink)?
    @ObservationIgnored private let snapshot: @Sendable () -> [ClaudeSession]
    @ObservationIgnored private let watchPaths: @Sendable () -> [String]
    @ObservationIgnored private let hasCandidates: @Sendable () -> Bool
    @ObservationIgnored private let watcher: any ClaudeFileWatching
    @ObservationIgnored private let cadence: ClaudeLiveCadence
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var posted: Set<String> = []
    @ObservationIgnored private var consumers: Set<String> = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var slowLoop: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var readAgain = false

    public init(source: ClaudeLiveSource, sink: (any ClaudeActivitySink)? = nil,
                watcher: any ClaudeFileWatching = DispatchFileWatcher(), cadence: ClaudeLiveCadence = .init()) {
        self.snapshot = { source.snapshot() }
        self.watchPaths = { source.watchPaths() }
        self.hasCandidates = { source.hasCandidates() }
        self.sink = sink
        self.watcher = watcher
        self.cadence = cadence
        self.sleep = { try await Task.sleep(for: $0) }
    }

    /// Test seam: any snapshot function, watcher and sleep.
    public init(snapshot: @escaping @Sendable () -> [ClaudeSession],
                watchPaths: @escaping @Sendable () -> [String] = { [] },
                hasCandidates: @escaping @Sendable () -> Bool = { true },
                watcher: any ClaudeFileWatching = DispatchFileWatcher(),
                sink: (any ClaudeActivitySink)? = nil,
                cadence: ClaudeLiveCadence = .init(),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.snapshot = snapshot
        self.watchPaths = watchPaths
        self.hasCandidates = hasCandidates
        self.watcher = watcher
        self.sink = sink
        self.cadence = cadence
        self.sleep = sleep
    }

    // MARK: consumers

    public var isRunning: Bool { !consumers.isEmpty }

    /// A named consumer needs live sessions. The first one starts the monitor; naming the same one twice counts once.
    public func acquire(_ consumer: String) {
        let wasIdle = consumers.isEmpty
        consumers.insert(consumer)
        if wasIdle { begin() }
    }

    /// The last consumer to leave stops the watchers and the poll and withdraws every activity.
    public func release(_ consumer: String) {
        consumers.remove(consumer)
        if consumers.isEmpty { end() }
    }

    public func start() { acquire("default") }
    public func stop() { release("default") }

    // MARK: lifecycle

    private func begin() {
        generation += 1
        let mine = generation
        // Arm what exists now (cheap, and the first events cannot be missed), then read once.
        slowLoop = Task { [weak self, sleep] in
            await self?.slowTick(generation: mine)
            while !Task.isCancelled {
                guard let wait = self?.slowDelay() else { return }
                do { try await sleep(wait) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.slowTick(generation: mine)
            }
        }
    }

    private func end() {
        generation += 1
        slowLoop?.cancel(); slowLoop = nil
        debounce?.cancel(); debounce = nil
        reading = false
        readAgain = false
        watcher.stop()
        apply([])
    }

    private func slowDelay() -> Duration? {
        guard isRunning else { return nil }
        return sessions.isEmpty ? cadence.slowIdle : cadence.slowWithSessions
    }

    /// The watcher's callback: first event of a burst opens the debounce window.
    private func eventArrived(generation mine: Int) {
        guard mine == generation, isRunning, debounce == nil else { return }
        debounce = Task { [weak self, sleep, delay = cadence.debounce] in
            do { try await sleep(delay) } catch { return }
            guard let self, !Task.isCancelled, self.generation == mine else { return }
            self.debounce = nil
            await self.read(generation: mine)
        }
    }

    private func rearm(_ paths: [String], generation mine: Int) {
        guard mine == generation else { return }
        watcher.watch(paths) { [weak self] in
            Task { @MainActor in self?.eventArrived(generation: mine) }
        }
    }

    /// The slow path: re-arm, then read only when a session file exists.
    private func slowTick(generation mine: Int) async {
        let paths = watchPaths, candidates = hasCandidates
        let (armed, any) = await Task.detached(priority: .utility) { (paths(), candidates()) }.value
        guard mine == generation else { return }
        rearm(armed, generation: mine)
        if any {
            await read(generation: mine)
        } else if !sessions.isEmpty {
            apply([])   // the files are gone: so are the sessions
        }
    }

    /// One read; a request made while one runs makes it run once more instead of overlapping.
    private func read(generation mine: Int) async {
        guard mine == generation else { return }
        if reading { readAgain = true; return }
        reading = true
        defer { if mine == generation { reading = false } }
        repeat {
            readAgain = false
            let read = snapshot, paths = watchPaths
            let (fresh, armed) = await Task.detached(priority: .utility) { (read(), paths()) }.value
            // stop() may have run while the read was in flight: its result must not be posted.
            guard mine == generation, !Task.isCancelled else { return }
            apply(fresh)
            rearm(armed, generation: mine)   // a session file that appeared or went away
        } while readAgain && mine == generation
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
