import IslandKit
import IslandUI
import SwiftUI

/// The open island's content, clipped to the growing shape (`IslandRevealShape`), faded in by `IslandRevealCurve`.
///
/// Same look as `IslandOpenReveal` minus the 97 % -> 100 % scale. That scale is what broke the home: once the
/// reveal reaches 1 the scale change leaves the lower part of the body undrawn (the tile rows are cut about
/// 12 pt under their top, some round-button glyphs go missing), and it stays so until the route changes.
/// Reproduced by bisection in a live (windowed) `NSHostingView`: the scale alone is enough, opacity, backdrop and
/// clip are fine; `HomeNavigationRenderTests` guards it. Do not put a `scaleEffect` back on this subtree.
struct HomeOpenReveal: ViewModifier, Animatable {
    var progress: Double
    let closedSize: CGSize
    var closedOffset: CGFloat = 0
    let translucent: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(IslandRevealCurve.contentOpacity(progress: progress))
            .background {
                IslandRevealShape(progress: progress, closedSize: closedSize, closedOffset: closedOffset)
                    .fill(IslandSurface.notchBlack)
                    .opacity(IslandRevealCurve.backdropOpacity(progress: progress, translucent: translucent))
            }
            .clipShape(IslandRevealShape(progress: progress, closedSize: closedSize, closedOffset: closedOffset))
    }
}
