import IslandUI
import SwiftUI

/// A horizontal meter: a fill (nil = unknown, nothing drawn) and a thin pace marker.
struct AgentsMeter: View {
    let fill: Double?
    let marker: Double?
    var tint: Color = IslandPalette.accent.color

    private static let barHeight = IslandMetrics.hudBarHeight

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(IslandPalette.textPrimary.color.opacity(0.14))
                    .frame(height: Self.barHeight)
                if let fill {
                    Capsule().fill(tint)
                        .frame(width: max(0, min(1, fill)) * width, height: Self.barHeight)
                }
                if let marker {
                    Rectangle()
                        .fill(IslandPalette.textPrimary.color)
                        .frame(width: 2, height: Self.barHeight + 6)
                        .offset(x: max(0, min(1, marker)) * width - 1)
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: Self.barHeight + 6)
        .clipped()
        .accessibilityHidden(true)
    }
}
