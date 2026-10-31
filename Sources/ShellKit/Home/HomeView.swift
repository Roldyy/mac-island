import IslandUI
import SwiftUI

/// The Spacieuse home: three sliders, the now-playing card and the grid of quick tiles.
/// Sits inside the black body, below the notch band.
struct HomeView: View {
    let context: ShellContext
    /// The island is open: only then are the levels polled.
    var isActive = true

    var body: some View {
        let home = context.home
        VStack(spacing: HomeGeometry.gap) {
            HStack(spacing: IslandSpacing.m) {
                HomeLevelSlider(level: home.volume)
                HomeLevelSlider(level: home.brightness)
                HomeLevelSlider(level: home.keyboardLight)
            }
            .frame(height: HomeGeometry.slidersRow)
            HomeNowPlayingCard(track: home.track) { home.transport($0) }
            tiles(home.tileActions)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IslandSpacing.l - 2)
        .task(id: isActive) {
            // A volume key or the Control Center moves the level while the island is open.
            // The content is still invisible during the first frames of the open animation: read after them.
            if isActive { try? await Task.sleep(for: .milliseconds(60)) }
            while isActive, !Task.isCancelled {
                home.refreshLevels()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Plain rows (not a lazy grid): the layout is small and fixed, and it renders in snapshots.
    private func tiles(_ actions: [HomeAction]) -> some View {
        let columns = HomeGeometry.tileColumns
        let rows = stride(from: 0, to: actions.count, by: columns).map { Array(actions[$0..<min($0 + columns, actions.count)]) }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row) { HomeTile(action: $0, context: context) }
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .frame(height: HomeGeometry.tileRow)
            }
        }
    }
}
