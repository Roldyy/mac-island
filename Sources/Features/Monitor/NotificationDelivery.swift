import Foundation
import UserNotifications

enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
    /// No app bundle (for example `swift run`): `UNUserNotificationCenter` cannot be used.
    case unavailable
}

protocol NotificationDelivering {
    var hasBundle: Bool { get }
    func authorizationStatus() async -> NotificationAuthorization
    /// Shows the system prompt. Only ever called from a button the user pressed.
    func requestAuthorization() async -> Bool
    func post(title: String, body: String)
}

/// `UNUserNotificationCenter.current()` traps without a bundle identifier, so it is touched only
/// after the `hasBundle` check, and never at construction time.
struct SystemNotificationCenter: NotificationDelivering {
    var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    func authorizationStatus() async -> NotificationAuthorization {
        guard hasBundle else { return .unavailable }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        guard hasBundle else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    func post(title: String, body: String) {
        guard hasBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // One identifier: a new alert replaces the previous one instead of stacking.
        let request = UNNotificationRequest(identifier: "be.roldy.macisland.monitor.alert",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
