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
    public var settingsURL: URL? { privacyPane.url }

    public init?(_ permission: FeaturePermission) {
        switch permission {
        case .accessibility: self = .accessibility
        case .screenRecording: self = .screenRecording
        default: return nil
        }
    }

    /// Features whose key tap needs Input Monitoring on top of what their descriptor lists
    /// (`KeyEventTap` checks `CGPreflightListenEventAccess`). Cleaning mode is the ported `cleaningMode` feature now
    /// and needs Accessibility only, like the other ported taps (below).
    /// The Finder stays listed: since lane W7-A its ported taps are active ones (Accessibility only), but this row
    /// and the tests that pin it are left for the permissions follow-up.
    static let inputMonitoringFeatureIDs: Set<String> = ["finder"]

    /// The ported (Vorssaint) tap features: the permissions a grant must restart them for. Derived from the
    /// ported feature catalog's permission table (`AppFeature.permissions`), not guessed: every one of these
    /// is `[.accessibility]` there, and each of their taps is an active `.defaultTap`, which needs
    /// Accessibility and not Input Monitoring (a listen-only tap would). `mouseAcceleration` lists none: it
    /// changes a system setting and installs no tap. `PortFeatureBinding` builds the same permissions into
    /// each descriptor, so `used(by:)` agrees either way; this table is the pinned statement, and a test
    /// compares the two. Keys are registry ids (= upstream raw ids for features new to Mac Island).
    static let portedFeaturePermissions: [String: Set<MonitoredPermission>] = [
        "scrollInverter": [.accessibility],
        "scrollHorizontal": [.accessibility],
        "smoothScroll": [.accessibility],
        "linearScroll": [.accessibility],
        "mouseAcceleration": [],
        "mouseNavigation": [.accessibility],
        "mouseButtonShortcuts": [.accessibility],
        "middleClick": [.accessibility],
        "mouseClickDebounce": [.accessibility],
        "focusFollowsMouse": [.accessibility],
        "keyboardDebounce": [.accessibility],
        "superKey": [.accessibility],
        "quitWindowProtection": [.accessibility],
        "textSnippets": [.accessibility],
        "cleaningMode": [.accessibility],
    ]

    public static func used(by descriptor: FeatureDescriptor) -> Set<MonitoredPermission> {
        var used = Set(descriptor.permissions.compactMap(MonitoredPermission.init))
        if inputMonitoringFeatureIDs.contains(descriptor.id) { used.insert(.inputMonitoring) }
        used.formUnion(portedFeaturePermissions[descriptor.id] ?? [])
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
