import IslandUI
import SwiftUI

/// Three bars that dance while music plays. Sized by frame, not by font, so nothing here is below 11 pt text.
struct AmbientEqualizer: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var ambient = AmbientClock.shared

    private static let height: CGFloat = 11

    var body: some View {
        TimelineView(.animation(
            minimumInterval: AmbientClockPolicy.interval(forFPS: AmbientClockPolicy.equalizerFPS),
            paused: !AmbientClockPolicy.animationsRun(ambient.inputs, reduceMotion: reduceMotion))) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: Self.height * AmbientMotion.barLevel(index, time: time, reduceMotion: reduceMotion))
                }
            }
            .frame(height: Self.height, alignment: .bottom)
        }
    }
}
