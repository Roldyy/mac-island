import AppKit
import SwiftTerm

/// SwiftTerm view that records when output last arrived and reports the first click,
/// so the island can hand the keyboard over before the terminal becomes first responder.
final class ActivityTerminalView: LocalProcessTerminalView {
    private(set) var lastOutputAt = Date()
    var onClick: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutputAt = Date()
        super.dataReceived(slice: slice)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }
}
