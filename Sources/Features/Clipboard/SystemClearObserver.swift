import AppKit

/// "Vider le presse-papiers à la mise en veille du Mac / à l'extinction de l'écran / au verrouillage": each trigger
/// has its own observer, wanted or not from the settings, so it works with the others (and the delay) switched off.
/// Only the system pasteboard is cleared; the saved history is never touched.
@MainActor
final class SystemClearObserver {
    /// There is no AppKit constant for the lock notification; the app is not sandboxed, so it is delivered.
    nonisolated static let screenLockName = Notification.Name("com.apple.screenIsLocked")

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private var sleepToken: NSObjectProtocol?
    private var displaySleepToken: NSObjectProtocol?
    private var lockToken: NSObjectProtocol?
    private let onClear: @MainActor () -> Void

    init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
         onClear: @escaping @MainActor () -> Void) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.onClear = onClear
    }

    /// Adds or removes each observer so it matches the settings. Idempotent.
    func sync(sleep: Bool, displaySleep: Bool, lock: Bool) {
        sync(&sleepToken, wanted: sleep, name: NSWorkspace.willSleepNotification, center: workspaceCenter)
        sync(&displaySleepToken, wanted: displaySleep, name: NSWorkspace.screensDidSleepNotification, center: workspaceCenter)
        sync(&lockToken, wanted: lock, name: Self.screenLockName, center: distributedCenter)
    }

    func stop() { sync(sleep: false, displaySleep: false, lock: false) }

    var activeTriggers: (sleep: Bool, displaySleep: Bool, lock: Bool) {
        (sleepToken != nil, displaySleepToken != nil, lockToken != nil)
    }

    private func sync(_ token: inout NSObjectProtocol?, wanted: Bool, name: Notification.Name, center: NotificationCenter) {
        if wanted, token == nil {
            token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClear() }
            }
        } else if !wanted, let existing = token {
            center.removeObserver(existing)
            token = nil
        }
    }
}
