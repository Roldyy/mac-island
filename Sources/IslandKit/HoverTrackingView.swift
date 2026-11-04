import AppKit

/// Reports the pointer entering or leaving the island's hover zone through an `NSTrackingArea` of the panel
/// itself, so the app receives no mouse-moved event from the rest of the screen. It never takes a hit (clicks
/// go to the content under it) and never touches key status, so hovering cannot steal the keyboard.
final class HoverTrackingView: NSView {
    /// The hover zone in screen coordinates, asked again at every `refresh()`.
    var zone: () -> CGRect = { .zero }
    var onChange: () -> Void = {}
    private var area: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refresh()
    }

    /// Called whenever the panel frame or the open state changes.
    func refresh() {
        if let area { removeTrackingArea(area) }
        area = nil
        guard let window else { return }
        let rect = IslandHoverRegion.trackingRect(zone: zone(), panelFrame: window.frame)
        guard !rect.isEmpty else { return }
        let local = convert(rect, from: nil)
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        // The pointer may already sit in the zone (the island just opened under it): it must still report its exit.
        if zone().contains(NSEvent.mouseLocation) { options.insert(.assumeInside) }
        let next = NSTrackingArea(rect: local, options: options, owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { onChange() }
    override func mouseExited(with event: NSEvent) { onChange() }
}
