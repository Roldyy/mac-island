import Foundation
import SwiftUI

/// Timing and shape of the closed island's small animations, as pure functions so they can be tested
/// without a view. Every one of them has a still version for Reduce Motion.
public enum AmbientMotion {
    /// Width and content changes of the strip: a quick spring with a hint of overshoot.
    public static let morph = Animation.spring(response: 0.38, dampingFraction: 0.78)

    /// Seconds the title waits at each end before it moves.
    public static let marqueePause: TimeInterval = 1.4
    /// Points per second.
    public static let marqueeSpeed: Double = 22

    /// Where a long title sits, 0 (start) to 1 (end of its travel), at time `t`: it waits, scrolls to the end,
    /// waits, and scrolls back. 0 when there is nothing to scroll.
    public static func marqueePhase(time t: TimeInterval, travel: CGFloat) -> Double {
        guard travel > 1, t.isFinite else { return 0 }
        let move = Double(travel) / marqueeSpeed
        let cycle = 2 * (marqueePause + move)
        var local = t.truncatingRemainder(dividingBy: cycle)
        if local < 0 { local += cycle }
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        if local < marqueePause { return 0 }
        local -= marqueePause
        if local < move { return ease(local / move) }
        local -= move
        if local < marqueePause { return 1 }
        local -= marqueePause
        return 1 - ease(min(local / move, 1))
    }

    /// Height of equalizer bar `index` (0...2) as a fraction of the full height. Still under Reduce Motion.
    public static func barLevel(_ index: Int, time t: TimeInterval, reduceMotion: Bool) -> Double {
        let still: [Double] = [0.55, 0.95, 0.72]
        let i = min(max(index, 0), still.count - 1)
        guard !reduceMotion, t.isFinite else { return still[i] }
        let speeds: [Double] = [5.1, 6.3, 4.4], phases: [Double] = [0, 1.7, 3.1]
        return 0.3 + 0.7 * abs(sin(t * speeds[i] + phases[i]))
    }

    /// Strength of the one-off pulse of an urgent indicator at progress `p` (0 start, 1 over): a single swell.
    public static func pulseSwell(_ p: Double) -> Double {
        guard p.isFinite else { return 0 }
        return sin(Double.pi * min(max(p, 0), 1))
    }
}

/// Opacity, scale and blur of an indicator that comes or goes. Amount 1 is fully gone.
struct AmbientSwapEffect: ViewModifier {
    var amount: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .scaleEffect(1 - 0.3 * amount)
            .blur(radius: 5 * amount)
    }
}

extension AnyTransition {
    /// Crossfade with blur and a small scale; nothing at all under Reduce Motion.
    static func ambientSwap(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .modifier(active: AmbientSwapEffect(amount: 1), identity: AmbientSwapEffect(amount: 0))
    }
}
