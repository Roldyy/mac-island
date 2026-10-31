import IslandUI
import SwiftUI

/// A horizontal meter: a fill (nil = unknown, nothing drawn) and a thin pace marker.
struct AgentsMeter: View {
    let fill: Double?
    let marker: Double?
    var tint: Color = IslandPalette.accent.color
    var barHeight: CGFloat = IslandMetrics.hudBarHeight

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(IslandPalette.textPrimary.color.opacity(0.14))
                    .frame(height: barHeight)
                if let fill {
                    Capsule().fill(tint)
                        .frame(width: max(0, min(1, fill)) * width, height: barHeight)
                }
                if let marker {
                    Rectangle()
                        .fill(IslandPalette.textPrimary.color)
                        .frame(width: 2, height: barHeight + 6)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .offset(x: max(0, min(1, marker)) * width - 1)
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: barHeight + 6)
        .clipped()
        .accessibilityHidden(true)
    }
}
