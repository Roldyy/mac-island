import Foundation
import Observation

/// Something that fires `tick` every `interval` seconds until stopped. Faked in tests.
@MainActor
public protocol PermissionPollScheduler: AnyObject {
    func start(interval: TimeInterval, tick: @escaping @MainActor () -> Void)
    func stop()
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

/// Re-reads the permissions on activation, on the Accessibility notification and on a 1 s poll while a
/// permission some enabled feature needs is missing, and reports a change only when the answer differs.
/// Never asks for a permission. The poll runs whether or not the Settings window is open.
@MainActor @Observable
public final class PermissionMonitor {
    public static let pollInterval: TimeInterval = 1
    /// Extra polls after the Accessibility notification: it can arrive just before the answer flips.
    static let burstPolls = 5

    /// Last reading. Assigned only when it differs, so observers redraw for real changes only.
    public private(set) var snapshot: PermissionSnapshot
    /// Permissions the user went to grant that the process still reads as missing; see `PermissionTracker`.
    public private(set) var staleSuspected: Set<MonitoredPermission> = []
    public private(set) var isPolling = false

    @ObservationIgnored private var tracker: PermissionTracker
    @ObservationIgnored private var burst = 0
    @ObservationIgnored private let read: @MainActor () -> PermissionSnapshot
    @ObservationIgnored private let needed: @MainActor () -> Set<MonitoredPermission>
    @ObservationIgnored private let scheduler: PermissionPollScheduler
    @ObservationIgnored private let triggers: PermissionTriggerSource?
    @ObservationIgnored private let onChange: @MainActor (PermissionChange) -> Void

    public init(read: @escaping @MainActor () -> PermissionSnapshot,
                needed: @escaping @MainActor () -> Set<MonitoredPermission> = { Set(MonitoredPermission.allCases) },
                scheduler: PermissionPollScheduler,
                triggers: PermissionTriggerSource? = nil,
                onChange: @escaping @MainActor (PermissionChange) -> Void = { _ in }) {
        let first = read()
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
        scheduler.stop()
        isPolling = false
    }

    /// The "Revérifier" button, a trigger, or a tick.
    public func recheck() {
        let new = read()
        if let change = tracker.observe(new) {
            snapshot = new
            onChange(change)
        }
        let stale = tracker.staleSuspected
        if stale != staleSuspected { staleSuspected = stale }
        updatePolling()
    }

    /// The user pressed "Autoriser": remember it, to tell a late grant from a grant that never lands.
    public func noteOpened(_ permission: MonitoredPermission) { tracker.noteOpened(permission) }

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

    private func updatePolling() {
        let wanted = burst > 0 || tracker.needsPolling(needed: needed())
        if wanted, !isPolling {
            isPolling = true
            scheduler.start(interval: Self.pollInterval) { [weak self] in self?.tick() }
        } else if !wanted, isPolling {
            scheduler.stop()
            isPolling = false
        }
    }

    private func tick() {
        if burst > 0 { burst -= 1 }
        recheck()
    }
}
