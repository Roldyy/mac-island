import Foundation
import IslandKit

/// The panes of System Settings, Privacy & Security, that Mac Island ever opens. ONE table: every permission kind
/// (`FeaturePermission` for the feature cards, `MonitoredPermission` for the three the monitor reads) maps to a
/// pane through here, so a click on "Autoriser" can never land on another permission's pane. A test pins the
/// whole table, anchor by anchor.
public enum PrivacyPane: String, CaseIterable, Sendable {
    case accessibility = "Privacy_Accessibility"
    case automation = "Privacy_Automation"
    case screenCapture = "Privacy_ScreenCapture"
    case microphone = "Privacy_Microphone"
    case camera = "Privacy_Camera"
    case listenEvent = "Privacy_ListenEvent"
    case allFiles = "Privacy_AllFiles"
    case calendars = "Privacy_Calendars"
    case bluetooth = "Privacy_Bluetooth"
    case audioCapture = "Privacy_AudioCapture"

    public static let urlPrefix = "x-apple.systempreferences:com.apple.preference.security?"

    /// The deep link of the pane. Opening it never asks for the permission.
    public var url: URL { URL(string: Self.urlPrefix + rawValue)! }
}

public extension FeaturePermission {
    /// The Privacy pane of this permission; nil for the two that live elsewhere in System Settings
    /// (Notifications, and Login Items for the system helper).
    var privacyPane: PrivacyPane? {
        switch self {
        case .accessibility: .accessibility
        case .screenRecording: .screenCapture
        case .automation: .automation
        case .audioCapture: .audioCapture
        case .camera: .camera
        case .microphone: .microphone
        case .calendar: .calendars
        case .bluetooth: .bluetooth
        case .fullDiskAccess: .allFiles
        case .notifications, .helperDaemon: nil
        }
    }
}

public extension MonitoredPermission {
    var privacyPane: PrivacyPane {
        switch self {
        case .accessibility: .accessibility
        case .inputMonitoring: .listenEvent
        case .screenRecording: .screenCapture
        }
    }
}
