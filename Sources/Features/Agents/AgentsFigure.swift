import IslandUI
import SwiftUI

/// A number that rolls to its new value instead of jumping. Still under Reduce Motion.
struct AgentsFigure: View {
    let text: String
    var font: Font = .system(size: 30, weight: .bold, design: .rounded)
    var color: Color = IslandPalette.textPrimary.color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .animation(IslandMotion.animation(.snappy(duration: 0.45), reduceMotion: reduceMotion), value: text)
    }
}
