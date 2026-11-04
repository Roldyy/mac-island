import CoreGraphics
import Foundation

/// What decides whether the closed strip is on screen. Plain values so the decision is testable without a
/// window, a workspace or a clock.
public struct AmbientClockInputs: Equatable, Sendable {
    /// The island is open: the strip is replaced by the content.
    public var islandOpen: Bool
    /// The panel has no visible part (covered, on another Space, screen off): `NSWindow.occlusionState`.
    public var panelOccluded: Bool
    /// `NSWorkspace.screensDidSleep` / `willSleep` until the matching wake.
    public var screenAsleep: Bool
    /// False while the screen is locked or another user's session is in front.
    public var sessionActive: Bool

    public init(
        islandOpen: Bool = false, panelOccluded: Bool = false, screenAsleep: Bool = false, sessionActive: Bool = true
    ) {
        self.islandOpen = islandOpen
        self.panelOccluded = panelOccluded
        self.screenAsleep = screenAsleep
        self.sessionActive = sessionActive
    }
}

/// Pause, rate and schedule rules of the strip's animations. One policy, four animations.
public enum AmbientClockPolicy {
    public static let equalizerFPS: Double = 12
    public static let ringFPS: Double = 15
    public static let marqueeFPS: Double = 20

    public static func stripIsVisible(_ inputs: AmbientClockInputs) -> Bool {
        !inputs.islandOpen && !inputs.panelOccluded && !inputs.screenAsleep && inputs.sessionActive
    }

    /// Bars, ring and marquee: motion, so Reduce Motion stops them as well.
    public static func animationsRun(_ inputs: AmbientClockInputs, reduceMotion: Bool) -> Bool {
        stripIsVisible(inputs) && !reduceMotion
    }

    /// Elapsed time is information, not motion: it keeps ticking under Reduce Motion, but not out of sight.
    public static func textClockRuns(_ inputs: AmbientClockInputs) -> Bool {
        stripIsVisible(inputs)
    }

    /// Seconds between two redraws at `fps`; one second for a rate that makes no sense.
    public static func interval(forFPS fps: Double) -> TimeInterval {
        fps.isFinite && fps > 0 ? 1.0 / fps : 1
    }

    /// A title scrolls only when it does not fit its slot, and never under Reduce Motion.
    public static func marqueeRuns(textWidth: CGFloat, slot: CGFloat, reduceMotion: Bool) -> Bool {
        !reduceMotion && textWidth > slot
    }

    /// Seconds to wait before the next redraw of a time text: one second when seconds are shown, otherwise
    /// until the next minute boundary (a full minute when `date` is exactly on one).
    public static func textTick(showsSeconds: Bool, after date: Date) -> TimeInterval {
        if showsSeconds { return 1 }
        let seconds = date.timeIntervalSince1970
        let into = seconds - (seconds / 60).rounded(.down) * 60
        return 60 - into
    }
}
