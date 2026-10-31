import SwiftUI

/// Every animation of the app goes through here so Reduce Motion cuts it in one place.
public enum IslandMotion {
    public static let standard = Animation.easeInOut(duration: 0.18)
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    /// `nil` (no animation) when Reduce Motion is on.
    public static func animation(_ animation: Animation? = standard, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// A plain fade under Reduce Motion, fade plus slight scale otherwise.
    public static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
}

private struct IslandAnimationModifier<Value: Equatable>: ViewModifier {
    private let display = IslandDisplay()
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(IslandMotion.animation(animation, reduceMotion: display.options.reduceMotion), value: value)
    }
}

public extension View {
    /// Drop-in for `.animation(_:value:)` that stays still under Reduce Motion.
    func islandAnimation<Value: Equatable>(_ animation: Animation? = IslandMotion.standard, value: Value) -> some View {
        modifier(IslandAnimationModifier(animation: animation, value: value))
    }
}
