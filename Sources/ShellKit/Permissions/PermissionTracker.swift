import Foundation

/// Pure state of the permission monitor: the last snapshot, which panes the user opened, and whether a
/// permission still reads "missing" after the user came back from System Settings.
public struct PermissionTracker: Equatable, Sendable {
    /// Observations (activation, notification, poll) that must still read "missing" after the user came
    /// back before the monitor suspects the process cannot see the grant (about 3 s at a 1 s poll).
    public static let staleAfterObservations = 4

    public private(set) var snapshot: PermissionSnapshot
    private var opened: Set<MonitoredPermission> = []
    private var sinceReturn: [MonitoredPermission: Int] = [:]

    public init(initial: PermissionSnapshot) { snapshot = initial }

    /// The user pressed "Autoriser" for this permission: its pane is open.
    public mutating func noteOpened(_ permission: MonitoredPermission) {
        guard !snapshot[permission] else { return }
        opened.insert(permission)
        sinceReturn[permission] = nil
    }

    /// The app became active again: whatever pane was opened is now behind the user.
    public mutating func noteReturned() {
        for permission in opened where sinceReturn[permission] == nil { sinceReturn[permission] = 0 }
    }

    /// Records one reading. Returns the change when (and only when) it differs from the last one.
    public mutating func observe(_ new: PermissionSnapshot) -> PermissionChange? {
        for permission in Array(sinceReturn.keys) where !new[permission] { sinceReturn[permission, default: 0] += 1 }
        for permission in new.granted {
            opened.remove(permission)
            sinceReturn[permission] = nil
        }
        guard new != snapshot else { return nil }
        let change = PermissionChange(old: snapshot, new: new)
        snapshot = new
        return change
    }

    /// Permissions the user went to grant, that still read false well after coming back. The usual causes:
    /// macOS only applies Screen Recording after a relaunch, or the switch is on for another signature.
    public var staleSuspected: Set<MonitoredPermission> {
        Set(sinceReturn.filter { $0.value >= Self.staleAfterObservations && !snapshot[$0.key] }.keys)
    }

    /// True while a permission some enabled feature needs is missing.
    public func needsPolling(needed: Set<MonitoredPermission>) -> Bool {
        !snapshot.missing.isDisjoint(with: needed)
    }
}

/// Plain sentences for the Settings pages.
public enum PermissionHints {
    public static let stale = "Activé dans Réglages Système, mais Mac Island ne le voit pas encore. Relancez Mac Island pour appliquer. Si cela persiste, retirez Mac Island de la liste (bouton −), puis ajoutez-le de nouveau."

    public static func state(_ granted: Bool) -> String { granted ? "Autorisé" : "Non autorisé" }
}
