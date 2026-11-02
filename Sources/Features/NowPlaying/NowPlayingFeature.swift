import Foundation
import IslandKit
import SwiftUI

public enum NowPlayingFeature {
    /// One model for the tab and the closed island, so a track is read once.
    @MainActor static let model = NowPlayingModel.live()

    /// Keeps the last played track on this Mac for the idle home card. Created once, with its settings observer.
    @MainActor private static let lastTrack: LastTrackRecorder = {
        let defaults = AppDefaults.make() ?? .standard
        let recorder = LastTrackRecorder(isEnabled: { LastTrackSettings.isEnabled(defaults) })
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { recorder.settingsChanged() }
        }
        return recorder
    }()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "nowplaying", title: "Lecture", systemImage: "play.circle") {
            AnyView(NowPlayingTabView())
        }
    }

    /// Publishes the playing track as a music activity (a wing of the closed island) and withdraws it
    /// when playback stops. Polls only once the user has authorized Automation from the tab.
    /// Also keeps the last track ("Mémoriser la dernière lecture", on by default, local only).
    @MainActor public static func start(center: ActivityCenter? = nil) {
        let center = center ?? ActivityCenter.shared
        postedCenter = center
        let recorder = lastTrack
        model.onSnapshot = { snap in
            recorder.observe(snap, artwork: model.artwork)
            guard let snap, snap.isPlaying else { center.withdraw(id: "music"); return }
            let title = snap.title.count > 18 ? String(snap.title.prefix(17)) + "…" : snap.title
            center.post(IslandActivity(
                id: "music", source: "nowplaying", priority: .music,
                leading: CompactItem(symbol: "music.note", progress: snap.progress),
                trailing: CompactItem(symbol: "waveform", text: title)))
        }
        started = true
        model.setBackground(true)
        // Silent (never prompts): a permission that already stands starts the reading without a click.
        Task { await model.refreshNow() }
    }

    /// Switch off, kill switch, safe mode or quarantine: the closed-island music activity is withdrawn, the background
    /// poll ends and the Home card reads nothing, at once (it used to wait for the next launch). Idempotent; the tab
    /// still polls while it is on screen, as before.
    @MainActor public static func stop() {
        model.onSnapshot = nil
        model.setBackground(false)
        postedCenter?.withdraw(id: "music")
        started = false
    }

    @MainActor private static var postedCenter: ActivityCenter?

    // MARK: - The island home

    /// True once `start()` ran: a switched-off feature reads nothing for the Home either.
    @MainActor private static var started = false

    @MainActor public static var isStarted: Bool { started }

    /// The Home card reads this. Nothing (no player, no access) until the feature runs.
    @MainActor public static func homeReading() -> NowPlayingHomeReading {
        guard started else { return NowPlayingHomeReading(access: .needsAuthorization, track: nil, runningPlayer: nil) }
        return model.homeReading()
    }

    /// Runs after every reading and every change of access.
    @MainActor public static func observeHome(_ observer: @escaping @MainActor () -> Void) {
        model.addObserver(observer)
    }

    /// Reads now (silent permission check first).
    @MainActor public static func refreshForHome() async {
        guard started else { return }
        await model.refreshNow()
    }

    /// The home is open: poll every second, whatever the closed island shows. Closed: back to the slow poll.
    @MainActor public static func setHomeOpen(_ open: Bool) {
        guard started else { return }
        model.setHomeOpen(open)
    }

    @MainActor public static func sendFromHome(_ command: NowPlayingHomeCommand) {
        guard started else { return }
        let mapped: PlayerCommand = switch command {
        case .previous: .previous
        case .playPause: .playPause
        case .next: .next
        }
        model.send(mapped)
    }

    /// The card's "Autoriser" button: asks macOS for the Automation permission (or opens its pane after a refusal).
    /// Call it from a user click, never from anywhere else.
    @MainActor public static func requestAutomationFromHome() {
        guard started else { return }
        Task { await model.requestAutomation() }
    }
}

enum LastTrackSettings {
    static let flagKey = "notchRememberLastTrack"

    static func isEnabled(_ defaults: UserDefaults) -> Bool { defaults.object(forKey: flagKey) as? Bool ?? true }
}
