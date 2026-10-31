import IslandKit
import SwiftUI

public enum NowPlayingFeature {
    /// One model for the tab and the closed island, so a track is read once.
    @MainActor static let model = NowPlayingModel.live()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "nowplaying", title: "Lecture", systemImage: "play.circle") {
            AnyView(NowPlayingTabView())
        }
    }

    /// Publishes the playing track as a music activity (a wing of the closed island) and withdraws it
    /// when playback stops. Polls only once the user has authorized Automation from the tab.
    @MainActor public static func start(center: ActivityCenter? = nil) {
        let center = center ?? ActivityCenter.shared
        model.onSnapshot = { snap in
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
