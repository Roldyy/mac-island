import AppKit
import SwiftUI

/// Borderless, non-activating panel that DOES take the keyboard: it is shown only on an explicit
/// hotkey press. Esc and losing key status both dismiss it.
final class CommandBarPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: PanelGeometry.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Above the open island (NotchPanel sits at .screenSaver), or the bar hides behind it.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        setAccessibilityLabel("Barre de commandes")
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}

@MainActor
final class CommandBarPanelPresenter: CommandBarPresenting {
    private let model: CommandBarModel
    private var panel: CommandBarPanel?
    private var hiding = false

    init(model: CommandBarModel) { self.model = model }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()
        // A fresh hosting view per show resets the text field focus and the scroll position.
        panel.contentView = NSHostingView(rootView: CommandBarView(model: model, onClose: { [weak self] in self?.hide() }))
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen { panel.setFrame(PanelGeometry.frame(in: screen.visibleFrame), display: true) }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard let panel, panel.isVisible, !hiding else { return }
        hiding = true
        panel.orderOut(nil)
        hiding = false
    }

    private func makePanel() -> CommandBarPanel {
        let p = CommandBarPanel()
        p.onDismiss = { [weak self] in self?.hide() }
        return p
    }
}
