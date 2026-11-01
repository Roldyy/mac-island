import Foundation
import UserNotifications

/// The last known notification authorization, read by the capability probe without a system call.
///
/// `UNUserNotificationCenter.current()` ends the process when the app has no bundle identifier (`swift run`) or when its
/// bundle was replaced under it, so it is touched only behind `canUseCenter`. `refresh` reads the settings (never
/// prompts); `request` shows the system prompt and is called from the "Autoriser" click only.
public final class NotificationAuthorizationCache: @unchecked Sendable {
    public static let shared = NotificationAuthorizationCache()

    private let lock = NSLock()
    private var value: Bool?

    /// true / false once read, nil while unknown (no bundle, or never refreshed).
    public var granted: Bool? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    /// Test and host seam: set the reading directly.
    public func set(_ granted: Bool?) {
        lock.lock(); value = granted; lock.unlock()
    }

    static var canUseCenter: Bool {
        Bundle.main.bundleIdentifier != nil && FileManager.default.fileExists(atPath: Bundle.main.bundlePath)
    }

    /// Pure mapping of the system status: provisional and ephemeral count as granted.
    static func reading(for status: UNAuthorizationStatus) -> Bool? {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: nil
        }
    }

    /// Reads the settings (no prompt) and calls `done` on the main queue with the reading.
    public func refresh(done: (@Sendable (Bool?) -> Void)? = nil) {
        guard Self.canUseCenter else { set(nil); done?(nil); return }
        UNUserNotificationCenter.current().getNotificationSettings { [self] settings in
            let reading = Self.reading(for: settings.authorizationStatus)
            set(reading)
            DispatchQueue.main.async { done?(reading) }
        }
    }

    /// The system prompt. ONLY from a button the person pressed. `done` runs on the main queue with the new reading;
    /// when the system did not grant (it never asks twice), the caller opens the pane.
    public func request(done: @escaping @Sendable (Bool?) -> Void) {
        guard Self.canUseCenter else { done(nil); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [self] granted, _ in
            set(granted)
            DispatchQueue.main.async { done(granted) }
        }
    }
}
