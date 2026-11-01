import Foundation
import Observation

/// Something that fires `tick` every `interval` seconds until stopped. Faked in tests.
@MainActor
public protocol PermissionPollScheduler: AnyObject {
    func start(interval: TimeInterval, tick: @escaping @MainActor () -> Void)
    /// Same, with the slack the system may add to each fire so the wake-ups can be coalesced.
    func start(interval: TimeInterval, tolerance: TimeInterval, tick: @escaping @MainActor () -> Void)
    func stop()
}

public extension PermissionPollScheduler {
    func start(interval: TimeInterval, tolerance: TimeInterval, tick: @escaping @MainActor () -> Void) {
        start(interval: interval, tick: tick)
    }
}

/// Events that say "the answer may have changed, ask again".
public enum PermissionTrigger: Sendable {
    /// The app became active (the user came back from System Settings).
    case activated
    /// macOS posted `com.apple.accessibility.api`: the Accessibility list changed.
    case accessibilityChanged
}

@MainActor
public protocol PermissionTriggerSource: AnyObject {
    func install(_ handler: @escaping @MainActor (PermissionTrigger) -> Void)
}

/// Re-reads the permissions on activation, on the Accessibility notification and on a slow poll while a
/// permission some enabled feature needs is missing, and reports a change only when the answer differs.
/// Never asks for a permission. The poll runs whether or not the Settings window is open.
///
/// Cost: every reading is a TCC round trip (`AXIsProcessTrusted`, `CGPreflight*`), and a feature switched on
/// whose permission the user never grants would keep it running for ever. So the poll is bounded: 2.5 s with a
/// 1 s timer tolerance, and it STOPS after a minute without a change (the 5 s backoff it replaced showed up
/// in the unified log as a `TCCAccessRequest() IPC` on the main thread every 5 s, for ever, with every island
/// closed). What makes a grant feel instant is not the poll: activation, the Accessibility notification, the
/// Settings window opening and the "Revérifier" press re-read at once, and the notification is followed by a
/// short 1 s burst. Any change, trigger, "Revérifier" press or "Autoriser" press starts the poll again.
/// With a `backgroundRead` the timer's readings run off the main thread; only the result comes back.
@MainActor @Observable
public final class PermissionMonitor {
    public static let pollInterval: TimeInterval = 2.5
    /// Timer slack at the base rate: the system may fire a poll up to this late, to coalesce wake-ups.
    public static let pollTolerance: TimeInterval = 1
    /// Rate of the burst that follows the Accessibility notification.
    public static let burstInterval: TimeInterval = 1
    /// Extra polls after the Accessibility notification: it can arrive just before the answer flips.
    static let burstPolls = 5
    /// About a minute at the base rate: after this many polls with the same answer the poll stops.
    static let quietPollsBeforeIdle = 24

    /// Last reading. Assigned only when it differs, so observers redraw for real changes only.
    public private(set) var snapshot: PermissionSnapshot
    /// Permissions the user went to grant that the process still reads as missing; see `PermissionTracker`.
    public private(set) var staleSuspected: Set<MonitoredPermission> = []
    public private(set) var isPolling = false

    @ObservationIgnored private var tracker: PermissionTracker
    @ObservationIgnored private var burst = 0
    @ObservationIgnored private var quietPolls = 0
    @ObservationIgnored private var currentInterval: TimeInterval?
    @ObservationIgnored private var snapshotObservers: [@MainActor (PermissionSnapshot) -> Void] = []
    @ObservationIgnored private let read: @MainActor () -> PermissionSnapshot
    @ObservationIgnored private let needed: @MainActor () -> Set<MonitoredPermission>
    @ObservationIgnored private let scheduler: PermissionPollScheduler
    @ObservationIgnored private let triggers: PermissionTriggerSource?
    @ObservationIgnored private let onChange: @MainActor (PermissionChange) -> Void
    @ObservationIgnored private let backgroundRead: (@Sendable () -> PermissionSnapshot)?
    @ObservationIgnored private var tickRead: Task<Void, Never>?

    public init(read: @escaping @MainActor () -> PermissionSnapshot,
                needed: @escaping @MainActor () -> Set<MonitoredPermission> = { Set(MonitoredPermission.allCases) },
                scheduler: PermissionPollScheduler,
                triggers: PermissionTriggerSource? = nil,
                backgroundRead: (@Sendable () -> PermissionSnapshot)? = nil,
                onChange: @escaping @MainActor (PermissionChange) -> Void = { _ in }) {
        let first = read()
        self.backgroundRead = backgroundRead
        self.read = read
        self.needed = needed
        self.scheduler = scheduler
        self.triggers = triggers
        self.onChange = onChange
        snapshot = first
        tracker = PermissionTracker(initial: first)
    }

    /// Installs the triggers and starts the poll if something is missing.
    public func start() {
        triggers?.install { [weak self] trigger in self?.handle(trigger) }
        updatePolling()
    }

    public func stop() {
        tickRead?.cancel()
        tickRead = nil
        scheduler.stop()
        isPolling = false
        currentInterval = nil
    }

    /// Calls `handler` now with the current reading, then after every real change, before the registry hears
    /// of it. The app delegate copies each reading to the ported code this way.
    public func addSnapshotObserver(_ handler: @escaping @MainActor (PermissionSnapshot) -> Void) {
        snapshotObservers.append(handler)
        handler(snapshot)
    }

    /// The "Revérifier" button: a person is waiting, so the poll goes back to its base rate too.
    public func recheck() {
        quietPolls = 0
        refresh()
        updatePolling()
    }

    /// The user pressed "Autoriser": remember it, to tell a late grant from a grant that never lands.
    public func noteOpened(_ permission: MonitoredPermission) {
        tracker.noteOpened(permission)
        quietPolls = 0
    }

    /// One reading. True when the answer changed.
    @discardableResult
    private func refresh() -> Bool { apply(read()) }

    /// Records a reading taken on or off the main thread. True when the answer changed.
    private func apply(_ new: PermissionSnapshot) -> Bool {
        var changed = false
        if let change = tracker.observe(new) {
            changed = true
            snapshot = new
            for observer in snapshotObservers { observer(new) }
            onChange(change)
        }
        let stale = tracker.staleSuspected
        if stale != staleSuspected { staleSuspected = stale }
        return changed
    }

    /// Starts or stops the poll for the current switches, without reading. The registry calls this
    /// when a switch changes what is needed.
    public func refreshPolling() { updatePolling() }

    func handle(_ trigger: PermissionTrigger) {
        switch trigger {
        case .activated: tracker.noteReturned()
        case .accessibilityChanged: burst = Self.burstPolls
        }
        recheck()
    }

    /// Rate for now: the burst first, then the base rate.
    private var desiredInterval: TimeInterval { burst > 0 ? Self.burstInterval : Self.pollInterval }

    private func tolerance(for interval: TimeInterval) -> TimeInterval {
        interval == Self.burstInterval ? 0.1 : Self.pollTolerance
    }

    /// Starts, stops or re-rates the poll for the current need, without reading.
    private func updatePolling() {
        let idle = quietPolls >= Self.quietPollsBeforeIdle
        let wanted = burst > 0 || (!idle && tracker.needsPolling(needed: needed()))
        guard wanted else {
            if isPolling {
                scheduler.stop()
                isPolling = false
                currentInterval = nil
                if !idle { quietPolls = 0 }   // gone idle: stay idle until a trigger or a press says otherwise
            }
            return
        }
        let interval = desiredInterval
        guard !isPolling || interval != currentInterval else { return }
        isPolling = true
        currentInterval = interval
        scheduler.start(interval: interval, tolerance: tolerance(for: interval)) { [weak self] in self?.tick() }
    }

    private func tick() {
        if burst > 0 { burst -= 1 }
        guard let backgroundRead else { finishTick(changed: refresh()); return }
        guard tickRead == nil else { return }   // the previous reading has not come back yet
        tickRead = Task { [weak self] in
            let new = await Task.detached(priority: .utility) { backgroundRead() }.value
            guard let self, !Task.isCancelled else { return }
            self.tickRead = nil
            self.finishTick(changed: self.apply(new))
        }
    }

    private func finishTick(changed: Bool) {
        if changed { quietPolls = 0 } else { quietPolls += 1 }
        updatePolling()
    }
}
