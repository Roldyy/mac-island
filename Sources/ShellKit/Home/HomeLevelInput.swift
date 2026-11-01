import CoreGraphics

/// Pure mapping from a gesture to a slider level, so drag, scroll and keys are testable without a view.
enum HomeLevelInput {
    /// Level of one arrow key press or one VoiceOver step.
    static let keyStep = 0.0625

    /// Drag position -> level. A zero or negative width never divides by zero.
    static func level(forDragX x: CGFloat, width: CGFloat) -> Double {
        HomeLevel.clamped(Double(x / max(width, 1)))
    }

    /// Scroll delta -> new level. A trackpad (`precise`) reports points: 1 pt moves 0.4 %. A wheel reports lines:
    /// one notch moves 2 %. Scrolling up or to the right raises the level.
    static func level(from current: Double, scrollDelta: Double, precise: Bool) -> Double {
        guard scrollDelta.isFinite else { return current }
        let perUnit = precise ? 0.004 : 0.02
        return HomeLevel.clamped(current + scrollDelta * perUnit)
    }

    /// One key press (+1 / -1).
    static func level(from current: Double, keySteps: Int) -> Double {
        HomeLevel.clamped(current + Double(keySteps) * keyStep)
    }
}
