import Foundation
import IslandKit

/// The three system permissions whose grant arrives while the app runs and that decide whether an
/// already started feature can do its job. Input Monitoring has no `FeaturePermission` case (IslandKit
/// is frozen), so the monitor names it itself.
public enum MonitoredPermission: String, CaseIterable, Sendable, Hashable {
    case accessibility, inputMonitoring, screenRecording

    public var title: String {
        switch self {
        case .accessibility: "Accessibilité"
        case .inputMonitoring: "Surveillance de l'entrée"
        case .screenRecording: "Enregistrement de l'écran"
        }
    }

    /// Pane of System Settings to open. Opening it never asks for the permission.
    public var settingsURL: URL? {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_"
        switch self {
        case .accessibility: return URL(string: privacy + "Accessibility")
        case .inputMonitoring: return URL(string: privacy + "ListenEvent")
        case .screenRecording: return URL(string: privacy + "ScreenCapture")
        }
    }

    public init?(_ permission: FeaturePermission) {
        switch permission {
        case .accessibility: self = .accessibility
        case .screenRecording: self = .screenRecording
        default: return nil
        }
    }

    /// Features whose key tap needs Input Monitoring on top of what their descriptor lists
    /// (`KeyEventTap` and `CleaningEventTap` both check `CGPreflightListenEventAccess`).
    static let inputMonitoringFeatureIDs: Set<String> = ["finder"]

    public static func used(by descriptor: FeatureDescriptor) -> Set<MonitoredPermission> {
        var used = Set(descriptor.permissions.compactMap(MonitoredPermission.init))
        if inputMonitoringFeatureIDs.contains(descriptor.id) { used.insert(.inputMonitoring) }
        return used
    }
}

/// What the system answered for the three permissions at one moment.
public struct PermissionSnapshot: Equatable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var screenRecording: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.screenRecording = screenRecording
    }

    public subscript(_ permission: MonitoredPermission) -> Bool {
        switch permission {
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        case .screenRecording: screenRecording
        }
    }

    public var missing: Set<MonitoredPermission> { Set(MonitoredPermission.allCases.filter { !self[$0] }) }
    public var granted: Set<MonitoredPermission> { Set(MonitoredPermission.allCases.filter { self[$0] }) }
}

/// The difference between two snapshots.
public struct PermissionChange: Equatable, Sendable {
    public let old: PermissionSnapshot
    public let new: PermissionSnapshot
    public var granted: Set<MonitoredPermission> { new.granted.subtracting(old.granted) }
    public var revoked: Set<MonitoredPermission> { old.granted.subtracting(new.granted) }

    public init(old: PermissionSnapshot, new: PermissionSnapshot) {
        self.old = old
        self.new = new
    }
}
