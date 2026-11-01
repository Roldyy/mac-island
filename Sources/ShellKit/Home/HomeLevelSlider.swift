import IslandUI
import SwiftUI

/// Icon + slim bar + live percentage, like the top row of the island home. Dimmed with its reason when the system
/// refuses. Drag, scroll over it, or focus it and use the arrow keys.
struct HomeLevelSlider: View {
    let level: HomeLevel

    /// Fixed width of the percentage so three sliders reflow without the digits making the bars jump.
    static let valueWidth: CGFloat = 28

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
                    level.set(HomeLevelInput.level(forDragX: drag.location.x, width: proxy.size.width))
                })
            }
            .frame(height: HomeGeometry.slidersRow)
            Text(level.isAvailable ? IslandHUD.percentText(level.value) : "")
                .font(.system(size: IslandType.minimumSize, weight: .medium).monospacedDigit())
                .foregroundStyle(IslandPalette.textPrimary.color.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.valueWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .overlay { HomeScrollCatcher { delta, precise in
            level.set(HomeLevelInput.level(from: level.value, scrollDelta: delta, precise: precise))
        } }
        .focusable(level.isAvailable)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in
            switch press.key {
            case .rightArrow, .upArrow:
                level.set(HomeLevelInput.level(from: level.value, keySteps: 1))
                return .handled
            case .leftArrow, .downArrow:
                level.set(HomeLevelInput.level(from: level.value, keySteps: -1))
                return .handled
            default:
                return .ignored
            }
        }
        .opacity(level.isAvailable ? 1 : 0.4)
        .allowsHitTesting(level.isAvailable)
        .help(level.isAvailable ? level.title : "\(level.title) : \(level.unavailableReason)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.title)
        .accessibilityValue(level.isAvailable ? IslandHUD.percentText(level.value) : level.unavailableReason)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: level.set(HomeLevelInput.level(from: level.value, keySteps: 1))
            case .decrement: level.set(HomeLevelInput.level(from: level.value, keySteps: -1))
            @unknown default: break
            }
        }
    }
}
