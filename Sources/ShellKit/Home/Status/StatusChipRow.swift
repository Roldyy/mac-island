import IslandUI
import SwiftUI

/// The status chips of the open island: one horizontal row of capsules between the now-playing card and the extra
/// dock. The row scrolls sideways when the chips do not all fit and never grows taller.
///
/// While the feed has no reading (the switch is off, every enabled chip is still waiting for its first value) the row
/// draws nothing; the home keeps its height only while `StatusChipFeed.hasSlot`, so the layout does not jump.
struct StatusChipRow: View {
    let feed: StatusChipFeed

    var body: some View {
        let readings = feed.readings
        Group {
            if readings.isEmpty {
                Color.clear
            } else {
                ScrollView(.horizontal) { StatusChipStrip(readings: readings) }
                    .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: HomeGeometry.statusChipRow)
        .islandAnimation(.easeOut(duration: 0.12), value: readings.map(\.kind))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pastilles d’état")
    }
}
