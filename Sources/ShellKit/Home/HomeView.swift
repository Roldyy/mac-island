import IslandUI
import SwiftUI

/// The home: three sliders and the now-playing card (pinned), then the grid of every shortcut (it scrolls).
/// Sits inside the black body, below the notch band.
struct HomeView: View {
    let context: ShellContext
    /// The island is open: only then are the levels polled.
    var isActive = true

    var body: some View {
        let home = context.home
        let items = context.tileItems()
        VStack(spacing: HomeGeometry.gap) {
            // A level the system does not offer (no keyboard backlight) is left out: the others share the width.
            HStack(spacing: IslandSpacing.m) {
                ForEach(home.availableLevels, id: \.title) { HomeLevelSlider(level: $0) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: HomeGeometry.slidersRow)
            .help(home.unavailableLevelsHelp ?? "")
            HomeNowPlayingCard(track: home.track, idle: home.lastTrack) { home.transport($0) }
            HomeTileGrid(items: items, columns: home.tileColumns, visibleRows: home.tileRows(tileCount: items.count),
                         context: context)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IslandSpacing.l - 2)
        .task(id: isActive) {
            // A volume key or the Control Center moves the level while the island is open.
            // The content is still invisible during the first frames of the open animation: read after them.
            if isActive { try? await Task.sleep(for: .milliseconds(60)) }
            while isActive, !Task.isCancelled {
                home.refreshLevels()
                home.lastTrack.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
