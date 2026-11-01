import AppKit
import Foundation

/// A repeating `Timer` on the main run loop, in the common modes so it also fires while a menu is open.
@MainActor
final class TimerPollScheduler: PermissionPollScheduler {
    private var timer: Timer?

    func start(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// App activation and the Accessibility change notification, both delivered on the main queue.
@MainActor
final class SystemPermissionTriggers: PermissionTriggerSource {
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func install(_ handler: @escaping @MainActor (PermissionTrigger) -> Void) {
        guard tokens.isEmpty else { return }
        let local = NotificationCenter.default
        tokens.append((local, local.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler(.activated) }
        }))
        let distributed = DistributedNotificationCenter.default()
        tokens.append((distributed, distributed.addObserver(forName: Notification.Name("com.apple.accessibility.api"),
                                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler(.accessibilityChanged) }
        }))
    }
    // No deinit: the observers live as long as the app, which owns the monitor through the registry.
}

public extension PermissionMonitor {
    /// The monitor of the running app: live probe, real timer, real notifications. The registry keeps it
    /// (`registry.permissionMonitor`) and reacts to every change by starting or stopping features.
    @discardableResult
    static func attachLive(to registry: FeatureRegistry, probe: PermissionProbe) -> PermissionMonitor {
        let monitor = PermissionMonitor(
            read: { probe.snapshot() },
            needed: { [weak registry] in registry?.neededPermissions ?? [] },
            scheduler: TimerPollScheduler(),
            triggers: SystemPermissionTriggers(),
            onChange: { [weak registry] change in registry?.permissionsChanged(change) })
        registry.permissionMonitor = monitor
        monitor.start()
        return monitor
    }
}
