import SwiftUI

/// An urgent indicator swells once and sends out one ring when it appears (or turns urgent). Reduce Motion:
/// no motion at all, the amber or red symbol and text carry the state.
struct AmbientPulse: ViewModifier {
    let color: Color
    let isUrgent: Bool
    /// Tests and previews freeze the pulse at this progress (0...1) instead of running it.
    let preview: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fired = 0

    func body(content: Content) -> some View {
        if let preview {
            pulsed(content, progress: preview)
        } else if isUrgent, !reduceMotion {
            content
                .keyframeAnimator(initialValue: 1.0, trigger: fired) { view, progress in
                    pulsed(view, progress: progress)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.0, duration: 0.001)
                        CubicKeyframe(1.0, duration: 0.9)
                    }
                }
                .onAppear { fired += 1 }
        } else {
            content
        }
    }

    @ViewBuilder
    private nonisolated func pulsed<V: View>(_ view: V, progress: Double) -> some View {
        let swell = AmbientMotion.pulseSwell(progress)
        view
            .scaleEffect(1 + 0.06 * swell)
            .background {
                if isUrgent {
                    Capsule()
                        .strokeBorder(color.opacity(0.7 * (1 - progress)), lineWidth: 1.5)
                        .padding(-1 - 3 * progress)
                }
            }
    }
}
