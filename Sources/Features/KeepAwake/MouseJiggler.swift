import ApplicationServices
import CoreGraphics
import Foundation

protocol MouseJiggling: Sendable {
    func jiggle()
}

/// One pixel to the right and back through CGEvent. Needs Accessibility; the controller checks first.
struct CGEventMouseJiggler: MouseJiggling {
    func jiggle() {
        guard let here = CGEvent(source: nil)?.location else { return }
        let nudged = CGPoint(x: here.x + 1, y: here.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: nudged, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: here, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}

enum SystemProbes {
    /// Seconds since the last keyboard, mouse or trackpad event.
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Never prompts: the options dictionary is not passed.
    static func accessibilityTrusted() -> Bool { AXIsProcessTrusted() }
}
