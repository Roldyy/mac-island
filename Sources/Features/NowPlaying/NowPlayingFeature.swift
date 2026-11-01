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
        model.setBackground(true)
    }
}

enum LastTrackSettings {
    static let flagKey = "notchRememberLastTrack"

    static func isEnabled(_ defaults: UserDefaults) -> Bool { defaults.object(forKey: flagKey) as? Bool ?? true }
}
