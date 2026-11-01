import Foundation
import IslandKit
import Observation

/// Single source of truth for which features run. Never requests a permission: it only reads
/// capabilities through an injected provider and hands out the answer.
@MainActor @Observable
public final class FeatureRegistry {
    enum Keys {
        static let kill = "shell.killSwitch"
        static let safe = "shell.safeMode"
        static let seeded = "shell.hubSeeded"
        static func enabled(_ id: String) -> String { "shell.enabled.\(id)" }
        static func crashes(_ id: String) -> String { "shell.crashCount.\(id)" }
    }

    /// Two crashes at start quarantine a feature until the user clears it.
    public static let quarantineThreshold = 2

    @ObservationIgnored public let descriptors: [FeatureDescriptor]
    /// The user's switch per feature id; every id is present. Writes persist.
    public var switches: [String: Bool] {
        didSet { persistSwitches(old: oldValue); reconcile() }
    }
    public var killSwitch: Bool { didSet { defaults.set(killSwitch, forKey: Keys.kill); reconcile() } }
    public var safeMode: Bool { didSet { defaults.set(safeMode, forKey: Keys.safe); reconcile() } }
    public private(set) var quarantined: Set<String>
    public private(set) var capabilities: [String: FeatureCapability] = [:]

    /// Ids of features whose start() ran and that no stop() has undone.
    public private(set) var running: Set<String> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let crashMarker: CrashMarker
    @ObservationIgnored private let capabilityProvider: (FeatureDescriptor) -> FeatureCapability
    @ObservationIgnored private let withdraw: @MainActor (String) -> Void
    @ObservationIgnored private var starters: [String: @MainActor () -> Void] = [:]
    @ObservationIgnored private var stoppers: [String: @MainActor () -> Void] = [:]
    @ObservationIgnored private var activitySources: [String: String] = [:]
    @ObservationIgnored private var launched = false
    /// Features stopped because a permission they use was revoked, with the permissions still missing.
    @ObservationIgnored private var suspended: [String: Set<MonitoredPermission>] = [:]
    /// Set by `PermissionMonitor.attachLive`; the Settings pages read the live state and the stale hint from it.
    public var permissionMonitor: PermissionMonitor?

    /// `withdraw` drops what a stopped feature posted on the island (source name in, activities out).
    public init(descriptors: [FeatureDescriptor], defaults: UserDefaults, crashMarker: CrashMarker,
                capabilityProvider: @escaping (FeatureDescriptor) -> FeatureCapability = { _ in .available },
                withdraw: @escaping @MainActor (String) -> Void = { ActivityCenter.shared.withdrawAll(source: $0) }) {
        self.descriptors = descriptors
        self.defaults = defaults
        self.crashMarker = crashMarker
        self.capabilityProvider = capabilityProvider
        self.withdraw = withdraw
        self.killSwitch = defaults.bool(forKey: Keys.kill)
        self.safeMode = defaults.bool(forKey: Keys.safe)

        // A start flag still set means the previous launch died inside that feature's start().
        if let pending = crashMarker.pending() {
            crashMarker.clear()
            if descriptors.contains(where: { $0.id == pending }) {
                defaults.set(defaults.integer(forKey: Keys.crashes(pending)) + 1, forKey: Keys.crashes(pending))
            }
        }
        self.quarantined = Set(descriptors.map(\.id).filter {
            defaults.integer(forKey: Keys.crashes($0)) >= Self.quarantineThreshold
        })
        var stored: [String: Bool] = [:]
        for d in descriptors {
            stored[d.id] = defaults.object(forKey: Keys.enabled(d.id)) as? Bool ?? d.enabledByDefault
        }
        self.switches = stored
        refreshCapabilities()
    }

    /// The user's switch for one feature; lets a view bind to it with `$registry[feature: id]`.
    public subscript(feature id: String) -> Bool {
        get { switches[id] ?? false }
        set { switches[id] = newValue }
    }

    public func descriptor(_ id: String) -> FeatureDescriptor? { descriptors.first { $0.id == id } }

    public func refreshCapabilities() {
        let fresh = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, capabilityProvider($0)) })
        // Assigning an equal dictionary still publishes: the 1.5 s poll would redraw every page for nothing.
        if fresh != capabilities { capabilities = fresh }
        reconcile()  // a granted permission can make a feature available
    }

    public func state(for id: String) -> FeatureState {
        guard let d = descriptor(id) else { return .unavailable(reason: "Fonction inconnue") }
        if killSwitch { return .killed }
        if quarantined.contains(id) { return .quarantined }
        if safeMode && d.category != .daily { return .safeMode }
        if switches[id] != true { return .off }
        switch capabilities[id] ?? .available {
        case .available: return .active
        case .needsPermission(let p): return .needsPermission(p)
        case .unavailable(let reason): return .unavailable(reason: reason)
        }
    }

    public func isEnabled(_ id: String) -> Bool { state(for: id).isEnabled }

    // MARK: - Start flag

    /// Call right before a feature's start(); a crash inside it is charged to that feature.
    public func beginStart(_ id: String) { crashMarker.begin(id) }

    /// Call when start() returned: clears the flag and the feature's crash history.
    public func endStart(_ id: String) {
        if crashMarker.pending() == id { crashMarker.clear() }
        defaults.removeObject(forKey: Keys.crashes(id))
    }

    // MARK: - Start and stop

    /// Starts every enabled feature that has a starter, one at a time, each wrapped in the start flag, and
    /// keeps the closures: from now on every switch, safe mode or kill switch change starts or stops them.
    /// A feature with a starter and no stopper cannot be stopped live; see `needsRelaunch`.
    /// `activitySources` maps a feature id to the source name it posts under when that differs from the id.
    public func launch(starters: [String: @MainActor () -> Void],
                       stoppers: [String: @MainActor () -> Void] = [:],
                       activitySources: [String: String] = [:]) {
        self.starters = starters
        self.stoppers = stoppers
        self.activitySources = activitySources
        launched = true
        reconcile()
    }

    /// True when the user's switches ask for a stop that this feature cannot do while the app runs.
    public func needsRelaunch(_ id: String) -> Bool {
        running.contains(id) && stoppers[id] == nil && !isEnabled(id)
    }

    // MARK: - Permission changes

    /// Monitored permissions that at least one enabled feature uses; the monitor polls while one is missing.
    public var neededPermissions: Set<MonitoredPermission> {
        descriptors.filter { isEnabled($0.id) }.reduce(into: Set<MonitoredPermission>()) {
            $0.formUnion(MonitoredPermission.used(by: $1))
        }
    }

    /// A grant restarts each running feature that uses it (start() ran while the permission was missing and
    /// armed nothing); a revoke stops them until it is back. Features with no stopper are left alone.
    public func permissionsChanged(_ change: PermissionChange) {
        for d in descriptors where stoppers[d.id] != nil {
            let used = MonitoredPermission.used(by: d)
            let lost = used.intersection(change.revoked)
            if !lost.isEmpty, running.contains(d.id) { suspended[d.id, default: []].formUnion(lost) }
            let back = used.intersection(change.granted)
            guard !back.isEmpty else { continue }
            if var missing = suspended[d.id] {
                missing.subtract(back)
                suspended[d.id] = missing.isEmpty ? nil : missing  // reconcile starts it again once nothing is missing
            } else if running.contains(d.id), isEnabled(d.id) {
                stopForRestart(d)
            }
        }
        refreshCapabilities()
    }

    private func stopForRestart(_ d: FeatureDescriptor) {
        stoppers[d.id]?()
        withdraw(activitySources[d.id] ?? d.id)
        running.remove(d.id)
    }

    /// The "Autoriser" buttons call this next to opening the pane.
    public func noteOpened(_ permission: FeaturePermission) {
        if let p = MonitoredPermission(permission) { permissionMonitor?.noteOpened(p) }
    }

    /// Brings what runs in line with what `state(for:)` allows. Idempotent.
    private func reconcile() {
        guard launched else { return }
        defer { permissionMonitor?.refreshPolling() }
        for d in descriptors {
            guard let start = starters[d.id] else { continue }
            let wanted = isEnabled(d.id) && suspended[d.id] == nil
            if wanted && !running.contains(d.id) {
                beginStart(d.id)
                start()
                endStart(d.id)
                running.insert(d.id)
            } else if !wanted, running.contains(d.id), let stop = stoppers[d.id] {
                stop()
                withdraw(activitySources[d.id] ?? d.id)
                running.remove(d.id)
            }
        }
    }

    public func clearQuarantine(_ id: String) {
        defaults.removeObject(forKey: Keys.crashes(id))
        quarantined.remove(id)
    }

    // MARK: - Bundles and seeding

    public func apply(_ bundle: FeatureBundle) {
        let ids = bundle.ids(in: descriptors)
        var next = switches
        for d in descriptors { next[d.id] = ids.contains(d.id) }
        switches = next
    }

    /// One-shot seed from the old app's "kept features" value. When it names at least one known feature,
    /// the named ones start enabled and every other feature starts off, except where the user already
    /// chose. When it names none (missing, empty, unreadable) nothing changes. Returns false when it
    /// already ran.
    @discardableResult
    public func seedFromVorssaint(_ raw: Any?) -> Bool {
        guard !defaults.bool(forKey: Keys.seeded) else { return false }
        defer { defaults.set(true, forKey: Keys.seeded) }
        let named = VorssaintHubSeed.featureIDs(in: raw, descriptors: descriptors)
        guard !named.isEmpty else { return true }
        var next = switches
        for d in descriptors where defaults.object(forKey: Keys.enabled(d.id)) == nil {
            next[d.id] = named.contains(d.id)
        }
        switches = next
        return true
    }

    private func persistSwitches(old: [String: Bool]) {
        for (id, value) in switches where old[id] != value { defaults.set(value, forKey: Keys.enabled(id)) }
    }
}
