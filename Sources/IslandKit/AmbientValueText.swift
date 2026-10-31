import IslandUI
import SwiftUI

/// Width of a text as drawn, reported up to the view that decides whether it must scroll.
private struct AmbientTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The value next to a glyph: SF Rounded 11 pt with tabular digits, in a slot of fixed width so a changing
/// number never moves its neighbours. A title wider than its slot scrolls (cut with an ellipsis under
/// Reduce Motion).
struct AmbientValueText: View {
    let text: String
    let slot: CGFloat
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var natural: CGFloat = 0

    static var font: Font {
        .system(size: IslandType.caption, weight: .semibold, design: .rounded).monospacedDigit()
    }

    var body: some View {
        if AmbientMetrics.textWidth(text) > slot, !reduceMotion {
            marquee
        } else if AmbientMetrics.textWidth(text) > slot {
            Text(text)
                .font(Self.font)
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: slot, alignment: .leading)
        } else {
            // Never cut: the estimate only sets the room, the text keeps its own width if it is a little wider.
            Text(text)
                .font(Self.font)
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: slot, alignment: .leading)
                .contentTransition(.numericText())
        }
    }

    private var marquee: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let travel = max(0, natural - slot)
            let phase = AmbientMotion.marqueePhase(time: timeline.date.timeIntervalSinceReferenceDate, travel: travel)
            Text(text)
                .font(Self.font)
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { Color.clear.preference(key: AmbientTextWidthKey.self, value: $0.size.width) })
                .offset(x: -travel * phase)
                .frame(width: slot, alignment: .leading)
        }
        .onPreferenceChange(AmbientTextWidthKey.self) { natural = $0 }
        .clipped()
        .mask {
            // The ends fade, so a letter is never cut hard by the edge.
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 4)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 4)
            }
        }
    }
}
