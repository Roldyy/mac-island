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
        static let starting = "shell.startingFeature"
        static let seeded = "shell.hubSeeded"
        static func enabled(_ id: String) -> String { "shell.enabled.\(id)" }
        static func crashes(_ id: String) -> String { "shell.crashCount.\(id)" }
    }

    /// Two crashes at start quarantine a feature until the user clears it.
    public static let quarantineThreshold = 2

    @ObservationIgnored public let descriptors: [FeatureDescriptor]
    /// The user's switch per feature id; every id is present. Writes persist.
    public var switches: [String: Bool] {
        didSet { persistSwitches(old: oldValue) }
    }
    public var killSwitch: Bool { didSet { defaults.set(killSwitch, forKey: Keys.kill) } }
    public var safeMode: Bool { didSet { defaults.set(safeMode, forKey: Keys.safe) } }
    public private(set) var quarantined: Set<String>
    public private(set) var capabilities: [String: FeatureCapability] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let capabilityProvider: (FeatureDescriptor) -> FeatureCapability

    public init(descriptors: [FeatureDescriptor], defaults: UserDefaults,
                capabilityProvider: @escaping (FeatureDescriptor) -> FeatureCapability = { _ in .available }) {
        self.descriptors = descriptors
        self.defaults = defaults
        self.capabilityProvider = capabilityProvider
        self.killSwitch = defaults.bool(forKey: Keys.kill)
        self.safeMode = defaults.bool(forKey: Keys.safe)

        // A start flag still set means the previous launch died inside that feature's start().
        if let pending = defaults.string(forKey: Keys.starting) {
            defaults.removeObject(forKey: Keys.starting)
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
        capabilities = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, capabilityProvider($0)) })
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
    public func beginStart(_ id: String) { defaults.set(id, forKey: Keys.starting) }

    /// Call when start() returned: clears the flag and the feature's crash history.
    public func endStart(_ id: String) {
        if defaults.string(forKey: Keys.starting) == id { defaults.removeObject(forKey: Keys.starting) }
        defaults.removeObject(forKey: Keys.crashes(id))
    }

    /// Starts every enabled feature that has a starter, one at a time, each wrapped in the start flag.
    public func launch(starters: [String: @MainActor () -> Void]) {
        for d in descriptors where isEnabled(d.id) {
            guard let start = starters[d.id] else { continue }
            beginStart(d.id)
            start()
            endStart(d.id)
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

    /// One-shot seed from the old app's "kept features" value. Features it names start enabled unless the
    /// user already chose; the rest keep their default. Returns false when it already ran.
    @discardableResult
    public func seedFromVorssaint(_ raw: Any?) -> Bool {
        guard !defaults.bool(forKey: Keys.seeded) else { return false }
        defer { defaults.set(true, forKey: Keys.seeded) }
        let named = VorssaintHubSeed.featureIDs(in: raw, descriptors: descriptors)
        var next = switches
        for id in named where defaults.object(forKey: Keys.enabled(id)) == nil { next[id] = true }
        switches = next
        return true
    }

    private func persistSwitches(old: [String: Bool]) {
        for (id, value) in switches where old[id] != value { defaults.set(value, forKey: Keys.enabled(id)) }
    }
}
