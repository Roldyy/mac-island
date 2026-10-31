import Foundation

enum CleaningStartFailure: Equatable, Sendable {
    case needsAccessibility
    case needsInputMonitoring
    case refused
}

/// The event tap of cleaning mode, behind a protocol so the session is testable without a permission.
@MainActor
protocol CleaningTapping: AnyObject {
    /// `deadline` is a `ProcessInfo.systemUptime` value after which the tap lets everything through.
    func start(deadline: TimeInterval) -> CleaningStartFailure?
    func stop()
    var onEscape: (_ down: Bool, _ isRepeat: Bool) -> Void { get set }
    var onLost: () -> Void { get set }
}

/// Runs one cleaning period: tap + policy + a 0.25 s timer. It ends itself; `end` is safe to call twice.
@MainActor
final class CleaningSession {
    private(set) var policy: CleaningPolicy?
    private let tap: CleaningTapping
    private let clock: () -> Date
    private let uptime: () -> TimeInterval
    private let runsTimer: Bool
    private var timer: Timer?
    var onTick: (Int) -> Void = { _ in }
    var onEnd: (CleaningEnd) -> Void = { _ in }

    init(tap: CleaningTapping, clock: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         runsTimer: Bool = true) {
        self.tap = tap
        self.clock = clock
        self.uptime = uptime
        self.runsTimer = runsTimer
        tap.onEscape = { [weak self] down, rep in self?.escape(down: down, isRepeat: rep) }
        tap.onLost = { [weak self] in self?.end(.tapFailed) }
    }

    var isRunning: Bool { policy?.isRunning ?? false }

    /// Nil when cleaning started; otherwise why not (nothing is swallowed then).
    func start() -> CleaningStartFailure? {
        guard !isRunning else { return nil }
        let begin = clock()
        if let failure = tap.start(deadline: uptime() + CleaningPolicy.maxDuration) { return failure }
        policy = CleaningPolicy(start: begin)
        onTick(Int(CleaningPolicy.maxDuration))
        if runsTimer {
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        return nil
    }

    func tick() {
        guard var current = policy, current.isRunning else { return }
        let now = clock()
        let ended = current.tick(at: now)
        policy = current
        if let ended { finish(ended) } else { onTick(current.remainingSeconds(at: now)) }
    }

    func escape(down: Bool, isRepeat: Bool) {
        policy?.escape(down: down, isRepeat: isRepeat, at: clock())
    }

    func end(_ reason: CleaningEnd) {
        guard policy?.isRunning == true else { return }
        policy?.end(reason)
        finish(reason)
    }

    private func finish(_ reason: CleaningEnd) {
        timer?.invalidate()
        timer = nil
        tap.stop()
        onEnd(reason)
    }
}
