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
            HomeNowPlayingCard(track: home.track, idle: home.lastTrack, notice: home.nowPlayingNotice,
                               authorize: { home.nowPlaying.authorize() }) { home.transport($0) }
            // The status chips sit under the card; the row keeps its height while `hasSlot` (`HomeGeometry.statusChipSpace`).
            if home.statusChips.hasSlot { StatusChipRow(feed: home.statusChips) }
            // The extra dock sits between the card and the grid; its height is part of `HomeGeometry.fixedHeight`.
            if home.showsExtraDock { ExtraDockView(context: context) }
            HomeTileGrid(items: items, columns: home.tileColumns, visibleRows: home.tileRows(tileCount: items.count),
                         context: context)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IslandSpacing.l - 2)
        .onDisappear {
            home.nowPlaying.setOpen(false)
            home.statusChips.stop()
        }
        .task(id: isActive) {
            // Open: read the players at once and poll them fast; closed: stop (the closed island polls slowly).
            home.nowPlaying.setOpen(isActive)
            // The chips' sources sample only while the island is open.
            if isActive { home.statusChips.start() } else { home.statusChips.stop() }
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
