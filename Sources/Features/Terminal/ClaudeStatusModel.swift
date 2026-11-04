import Combine
import Foundation

/// What the status model reads: whether a shell exists, its pid, the last output, and whether Claude runs below it.
@MainActor
protocol ClaudeStatusSource: AnyObject {
    var hasSession: Bool { get }
    var shellPid: pid_t { get }
    var lastOutputAt: Date { get }
    func containsClaude(below pid: pid_t) -> Bool
}

/// The terminal session of the app and the process tree.
@MainActor
final class LiveClaudeStatusSource: ClaudeStatusSource {
    var hasSession: Bool { TerminalSession.shared.hasSession }
    var shellPid: pid_t { TerminalSession.shared.shellPid }
    var lastOutputAt: Date { TerminalSession.shared.lastOutputAt }
    func containsClaude(below pid: pid_t) -> Bool { ProcessTree.containsClaude(below: pid) }
}

/// Schedules a repeating tick and returns the closure that cancels it.
typealias ClaudeStatusTimerFactory = @MainActor (_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> () -> Void

/// Published Claude status. It is polled once a second only while a terminal shell exists (or while a "Terminé"
/// is still settling back to idle): no shell and an idle status mean no timer at all. The terminal session posts
/// `sessionChanged` when its shell starts or exits, which is what arms and re-checks the timer.
@MainActor
public final class ClaudeStatusModel: ObservableObject {
    /// Posted by `TerminalSession` when its shell starts or exits.
    static let sessionChanged = Notification.Name("be.roldy.macisland.terminal.sessionChanged")

    @Published public private(set) var status: ClaudeStatus = .idle

    private var tracker: ClaudeStatusTracker
    private let source: any ClaudeStatusSource
    private let makeTimer: ClaudeStatusTimerFactory
    private var cancelTimer: (() -> Void)?
    private var observer: NSObjectProtocol?
    private let center: NotificationCenter

    static let liveTimer: ClaudeStatusTimerFactory = { interval, tick in
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        timer.tolerance = 0.3   // the status changes on a scale of seconds: let the system coalesce the wakeups
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    public convenience init() {
        self.init(source: LiveClaudeStatusSource(), makeTimer: Self.liveTimer, center: .default,
                  tracker: ClaudeStatusTracker())
    }

    init(source: any ClaudeStatusSource, makeTimer: @escaping ClaudeStatusTimerFactory, center: NotificationCenter,
         tracker: ClaudeStatusTracker) {
        self.source = source
        self.makeTimer = makeTimer
        self.tracker = tracker
        self.center = center
        observer = center.addObserver(forName: Self.sessionChanged, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionChanged() }
        }
        reconcile()   // a shell that already runs when the model is created
    }

    deinit {
        cancelTimer?()
        if let observer { center.removeObserver(observer) }
    }

    private func sessionChanged() {
        poll()   // show the new state at once, not a second later
    }

    private func tick() { poll() }

    private func poll() {
        if source.hasSession {
            let running = source.containsClaude(below: source.shellPid)
            apply(tracker.update(claudeRunning: running, lastOutputAt: source.lastOutputAt))
        } else {
            // No shell: nothing can run. Let the tracker settle on idle/done without scanning processes.
            apply(tracker.update(claudeRunning: false, lastOutputAt: .distantPast))
        }
        reconcile()
    }

    /// One timer while it has something to watch: a shell, or a status that is not yet idle.
    private func reconcile() {
        let needed = source.hasSession || status != .idle
        if needed, cancelTimer == nil {
            cancelTimer = makeTimer(1) { [weak self] in self?.tick() }
        } else if !needed, let cancel = cancelTimer {
            cancel()
            cancelTimer = nil
        }
    }

    private func apply(_ new: ClaudeStatus) {
        if new != status { status = new }
    }
}
