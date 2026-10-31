import IslandUI
import SwiftUI

/// Icon + slim bar, like the top row of the island home. Dimmed with its reason when the system refuses.
struct HomeLevelSlider: View {
    let level: HomeLevel

    var body: some View {
        HStack(spacing: IslandSpacing.s - 2) {
            Image(systemName: level.systemImage)
                .font(.system(size: IslandType.minimumSize, weight: .semibold))
                .foregroundStyle(IslandPalette.textPrimary.color)
                .frame(width: 16)
                .accessibilityHidden(true)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(IslandPalette.textPrimary.color.opacity(0.22))
                    Capsule().fill(IslandPalette.textPrimary.color)
                        .frame(width: max(6, proxy.size.width * level.value))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    level.set(drag.location.x / max(proxy.size.width, 1))
                })
            }
            .frame(height: HomeGeometry.slidersRow)
        }
        .opacity(level.isAvailable ? 1 : 0.4)
        .allowsHitTesting(level.isAvailable)
        .help(level.isAvailable ? level.title : "\(level.title) : \(level.unavailableReason)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.title)
        .accessibilityValue(level.isAvailable ? IslandHUD.percentText(level.value) : level.unavailableReason)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: level.set(level.value + 0.0625)
            case .decrement: level.set(level.value - 0.0625)
            @unknown default: break
            }
        }
    }
}
