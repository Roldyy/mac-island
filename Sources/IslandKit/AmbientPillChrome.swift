import SwiftUI

/// The edge of the resting pill on a screen with no notch: a half-point highlight inside the outline, a little
/// brighter on top, and a faint sheen. Drawn inside the pill (the panel ends at its edge, so no outer shadow
/// can show). With a hardware notch nothing is drawn: the island must merge with the notch.
struct AmbientPillChrome: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandRevealCurve.closedBottomRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.clear], startPoint: .top, endPoint: .center))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
