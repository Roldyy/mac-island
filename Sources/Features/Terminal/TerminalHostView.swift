import AppKit
import IslandKit
import SwiftUI

/// Hosts the persistent SwiftTerm view. Hover never touches the keyboard: the first click asks the island
/// for it (`focusKeyboard`) and only then makes the terminal first responder.
struct TerminalHostView: NSViewRepresentable {
    @Environment(\.islandActions) private var actions

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container)
    }

    private func attach(to container: NSView) {
        let session = TerminalSession.shared
        let view = session.ensureRunning()
        let focus = actions.focusKeyboard
        view.onClick = { focus() }
        guard view.superview !== container else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}
