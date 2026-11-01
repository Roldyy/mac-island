import IslandUI
import SwiftUI

/// A thin horizontal bar between a glyph and its value (the volume). Fixed width, so a changing level never
/// moves its neighbours. The fill follows the level directly: no animation, so Reduce Motion needs no branch.
struct AmbientBar: View {
    let fill: Double
    let color: Color

    static let height: CGFloat = 4

    var body: some View {
        let level = CompactStrip.clampedProgress(fill)
        ZStack(alignment: .leading) {
            Capsule().fill(IslandPalette.textTertiary.color.opacity(0.35))
            Capsule().fill(color).frame(width: AmbientMetrics.barWidth * level)
        }
        .frame(width: AmbientMetrics.barWidth, height: Self.height)
        .accessibilityHidden(true)
    }
}
