import IslandUI
import SwiftUI

/// Lays out a side column (`.vertical`) or the bottom row (`.horizontal`) of round buttons inside the room it has.
///
/// While the buttons fit, the stack is plain: exactly the layout the island always had. When they do not
/// (`HomeButtonStack.needsScroll`), the stack becomes a scroll view of the room it has, with no indicators, a soft fade
/// at both ends and the content resting just inside the fade, so the island never grows and nothing overflows.
/// Wheel, trackpad and keyboard focus scroll it like any other scroll view; nothing animates, so Reduce Motion has
/// nothing to turn off.
struct HomeButtonStackView<Content: View>: View {
    let axis: Axis
    let count: Int
    /// Points available along the axis (`HomeButtonStack.sideAvailable` / `bottomAvailable`).
    let available: CGFloat
    /// Vertical only: space above the first button (under the notch band).
    var inset: CGFloat = 0
    @ViewBuilder let content: () -> Content

    private var scrolls: Bool {
        HomeButtonStack.needsScroll(count: count, item: HomeGeometry.circleDiameter,
                                    spacing: HomeButtonStack.spacing, available: available)
    }

    var body: some View {
        if !scrolls {
            if axis == .vertical { content().padding(.top, inset) } else { content() }
        } else if axis == .vertical {
            // The viewport starts `fade` above the first button (its resting margin) and ends at the foot of the body.
            let length = available + HomeButtonStack.fade
            ScrollView(.vertical) { content().frame(maxWidth: .infinity) }
                .scrollIndicators(.hidden)
                .contentMargins(.vertical, HomeButtonStack.fade, for: .scrollContent)
                .frame(height: length)
                .mask(Self.fadeMask(length: length, axis: .vertical))
                .padding(.top, inset - HomeButtonStack.fade)
        } else {
            ScrollView(.horizontal) { content().frame(maxHeight: .infinity) }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, HomeButtonStack.fade, for: .scrollContent)
                .frame(width: available, height: HomeGeometry.bottomRow)
                .mask(Self.fadeMask(length: available, axis: .horizontal))
        }
    }

    /// Opaque in the middle, transparent at both ends over `fade` points.
    private static func fadeMask(length: CGFloat, axis: Axis) -> some View {
        let edge = length > 0 ? min(HomeButtonStack.fade / length, 0.5) : 0
        return LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: edge),
                    .init(color: .black, location: 1 - edge), .init(color: .clear, location: 1)],
            startPoint: axis == .vertical ? .top : .leading,
            endPoint: axis == .vertical ? .bottom : .trailing)
    }
}
