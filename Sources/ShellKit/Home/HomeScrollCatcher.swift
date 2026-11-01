import AppKit
import SwiftUI

/// Receives scroll-wheel and trackpad scrolling over a view without taking the clicks and drags: the NSView only
/// claims the hit test while the current event is a scroll, so the SwiftUI gesture underneath keeps working.
struct HomeScrollCatcher: NSViewRepresentable {
    /// `delta`: positive for up / right; `precise`: a trackpad (points) rather than a wheel (lines).
    var onScroll: (_ delta: Double, _ precise: Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: ((Double, Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            // The dominant axis wins, so a diagonal flick does not cancel itself out.
            let x = Double(event.scrollingDeltaX), y = Double(event.scrollingDeltaY)
            let delta = abs(x) > abs(y) ? x : y
            guard delta != 0 else { return }
            onScroll?(delta, event.hasPreciseScrollingDeltas)
        }
    }
}
