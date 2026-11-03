import Foundation
import IslandKit
import Observation

/// The idle now-playing card: the last track kept on this Mac, and what a click on it does.
@MainActor @Observable
public final class LastTrackModel {
    /// Settings: "Mémoriser la dernière lecture". On unless the user switched it off.
    nonisolated public static let flagKey = "notchRememberLastTrack"

    public private(set) var record: LastTrackRecord?
    /// What a click does right now. Nil until the first `refresh()`.
    public private(set) var plan: PlayerOpenPlan?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: LastTrackStore
    @ObservationIgnored private let launcher: any PlayerLaunching
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var seenModification: Date?
    @ObservationIgnored private var planCheckedAt: Date?
    @ObservationIgnored private var planSettings: MusicPlayerSettings?

    /// How long an "installed or not" answer is reused: the tooltip does not need a Launch Services call per second.
    static let planLifetime: TimeInterval = 10

    public init(defaults: UserDefaults, store: LastTrackStore = .live,
                launcher: any PlayerLaunching = WorkspacePlayerLauncher(), now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.store = store
        self.launcher = launcher
        self.now = now
    }

    public var isEnabled: Bool { defaults.object(forKey: Self.flagKey) as? Bool ?? true }

    /// Label under the card title when nothing plays and no track is known.
    public var callToAction: String { plan?.title ?? "Ouvrir Spotify" }
    public var help: String { plan?.help ?? "Ouvrir Spotify" }

    /// Called while the island is open. Decodes the file only when it changed; switched off, forgets and deletes it.
    public func refresh() {
        guard isEnabled else {
            if record != nil || seenModification != nil || store.modificationDate() != nil { store.clear() }
            if record != nil { planCheckedAt = nil }
            record = nil
            seenModification = nil
            refreshPlan()
            return
        }
        let modified = store.modificationDate()
        if modified != seenModification || (modified == nil && record != nil) {
            seenModification = modified
            let loaded = modified == nil ? nil : store.load()
            if loaded != record {
                if loaded?.playerBundleID != record?.playerBundleID { planCheckedAt = nil }
                record = loaded
            }
        }
        refreshPlan()
    }

    private func refreshPlan() {
        let current = now()
        let settings = MusicPlayerSettings.read(from: defaults)
        // A changed player or blocker setting shows at once, not after the cached answer expires.
        if let checked = planCheckedAt, current.timeIntervalSince(checked) < Self.planLifetime, plan != nil,
           settings == planSettings { return }
        planCheckedAt = current
        planSettings = settings
        let fresh = PlayerOpenPlan.resolve(playerBundleID: record?.playerBundleID, settings: MusicPlayerSettings.read(from: defaults), launcher: launcher)
        if fresh != plan { plan = fresh }
    }

    /// Click on the card: open the player (the page to install Spotify when it is missing).
    public func open() {
        PlayerOpenPlan.resolve(playerBundleID: record?.playerBundleID, settings: MusicPlayerSettings.read(from: defaults), launcher: launcher).perform(with: launcher)
    }

    /// Play button of an idle card: a running player gets "play", otherwise it is launched.
    public func play(send: (HomeTransport) -> Void) {
        let plan = PlayerOpenPlan.resolve(playerBundleID: record?.playerBundleID, settings: MusicPlayerSettings.read(from: defaults), launcher: launcher)
        if case .launch(_, let bundleID, _) = plan, launcher.isRunning(bundleID: bundleID) {
            send(.playPause)
        } else {
            plan.perform(with: launcher)
        }
    }
}
