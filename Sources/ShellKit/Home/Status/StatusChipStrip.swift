import IslandUI
import SwiftUI

/// The capsules side by side, with no scrolling. `StatusChipRow` puts it in a horizontal scroll view; the render tests
/// draw it alone (a scroll view's content does not render through `ImageRenderer`).
struct StatusChipStrip: View {
    let readings: [StatusChipReading]

    var body: some View {
        HStack(spacing: IslandSpacing.xs) {
            ForEach(readings) { StatusChipView(reading: $0) }
        }
    }
}
