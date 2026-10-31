import IslandUI
import SwiftUI

/// Solid black behind the hardware notch, whatever the content draws on top: the notch has no
/// pixels, and a translucent or empty strip there would show the wallpaper around it.
struct NotchBackdrop<Content: View>: View {
    @EnvironmentObject private var state: IslandState
    let content: Content

    var body: some View {
        content.background(alignment: .top) {
            // IslandSurface.notchBlack once IslandUI provides it.
            Color.black.frame(width: state.notchWidth, height: state.notchHeight)
        }
    }
}

// MARK: - Open / close curve

/// Everything the open/close transition draws is a pure function of ONE progress value (0 closed, 1 open),
/// so a single animation drives the shape, its corners, the content fade and the content scale, and the
/// numbers are testable without a view. The panel itself is not resized per frame (see `IslandFramePlan`).
public enum IslandRevealCurve {
    public static let openDuration: TimeInterval = 0.34
    public static let closeDuration: TimeInterval = 0.26
    /// The panel keeps its larger frame this long after a shrink, so the shape can finish animating inside it.
    public static let settleDelay: TimeInterval = 0.42

    /// Content starts fading in once the shape has grown a little, and is fully in before it stops growing.
    public static let contentFadeStart = 0.4
    public static let contentFadeEnd = 0.9

    /// The resting pill: continuous corners, rounder than before so it reads as a pill on a screen with no notch.
    public static let closedTopRadius: CGFloat = 14
    public static let closedBottomRadius: CGFloat = 14
    public static let openTopRadius: CGFloat = 12
    public static let openBottomRadius: CGFloat = 26

    public static func clamp(_ p: Double) -> Double { p.isFinite ? min(max(p, 0), 1) : 0 }

    /// 0 below `from`, 1 above `to`, eased in between.
    public static func smoothstep(_ p: Double, from: Double, to: Double) -> Double {
        guard to > from else { return clamp(p) >= to ? 1 : 0 }
        let t = clamp((p - from) / (to - from))
        return t * t * (3 - 2 * t)
    }

    public static func shapeSize(progress p: Double, closed: CGSize, open: CGSize) -> CGSize {
        let t = CGFloat(clamp(p))
        return CGSize(width: closed.width + (open.width - closed.width) * t,
                      height: closed.height + (open.height - closed.height) * t)
    }

    public static func cornerRadii(progress p: Double) -> (top: CGFloat, bottom: CGFloat) {
        let t = CGFloat(clamp(p))
        return (closedTopRadius + (openTopRadius - closedTopRadius) * t,
                closedBottomRadius + (openBottomRadius - closedBottomRadius) * t)
    }

    /// Opening: the content stays hidden while the shape starts to grow. Closing (progress falling): it is
    /// the first thing to go, the shape shrinks around nothing.
    public static func contentOpacity(progress p: Double) -> Double {
        smoothstep(p, from: contentFadeStart, to: contentFadeEnd)
    }

    /// A slight settle: the content grows from 97 % to 100 % while it fades in.
    public static func contentScale(progress p: Double) -> Double {
        0.97 + 0.03 * smoothstep(p, from: 0.2, to: 1)
    }

    /// The closed strip hands over to the growing shape in the first quarter.
    public static func closedOpacity(progress p: Double) -> Double {
        1 - smoothstep(p, from: 0, to: 0.25)
    }

    /// Black fill under the growing shape, so the island never shows an empty frame while its content fades
    /// in. With a translucent body it hands over to the glass at the end; a solid body keeps it.
    public static func backdropOpacity(progress p: Double, translucent: Bool) -> Double {
        translucent ? 1 - smoothstep(p, from: 0.6, to: 1) : 1
    }

    public static func duration(opening: Bool, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : (opening ? openDuration : closeDuration)
    }

    /// One ease-out curve to open (fast start, no overshoot: the shape never leaves the panel), one ease-in-out
    /// to close. `nil` under Reduce Motion: the island simply appears.
    public static func animation(opening: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return opening
            ? .timingCurve(0.2, 0.85, 0.25, 1, duration: openDuration)
            : .timingCurve(0.4, 0, 0.6, 1, duration: closeDuration)
    }
}

/// The growing island outline, top-anchored in the rect it is given (the panel). At progress 1 it is the rect.
public struct IslandRevealShape: Shape {
    public var progress: Double
    public var closedSize: CGSize

    public init(progress: Double, closedSize: CGSize) {
        self.progress = progress
        self.closedSize = closedSize
    }

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let size = IslandRevealCurve.shapeSize(progress: progress, closed: closedSize, open: rect.size)
        let radii = IslandRevealCurve.cornerRadii(progress: progress)
        let frame = CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: size.height)
        return UnevenRoundedRectangle(
            topLeadingRadius: radii.top, bottomLeadingRadius: radii.bottom,
            bottomTrailingRadius: radii.bottom, topTrailingRadius: radii.top, style: .continuous
        ).path(in: frame)
    }
}

/// The open island's content, clipped to the growing shape. It is laid out once at its final size by the
/// caller; only the clip, the opacity and a tiny scale change per frame, so nothing is re-measured.
public struct IslandOpenReveal: ViewModifier, Animatable {
    public var progress: Double
    public let closedSize: CGSize
    public let translucent: Bool

    public init(progress: Double, closedSize: CGSize, translucent: Bool) {
        self.progress = progress
        self.closedSize = closedSize
        self.translucent = translucent
    }

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(IslandRevealCurve.contentScale(progress: progress), anchor: .top)
            .opacity(IslandRevealCurve.contentOpacity(progress: progress))
            .background {
                IslandRevealShape(progress: progress, closedSize: closedSize)
                    .fill(IslandSurface.notchBlack)
                    .opacity(IslandRevealCurve.backdropOpacity(progress: progress, translucent: translucent))
            }
            .clipShape(IslandRevealShape(progress: progress, closedSize: closedSize))
    }
}

/// The closed strip fades out as the shape takes over (and back in on close).
public struct IslandClosedReveal: ViewModifier, Animatable {
    public var progress: Double

    public init(progress: Double) { self.progress = progress }

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public func body(content: Content) -> some View {
        content.opacity(IslandRevealCurve.closedOpacity(progress: progress))
    }
}
