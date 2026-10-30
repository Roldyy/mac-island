import AppKit
import SwiftUI

@MainActor protocol PreviewPresenting: AnyObject {
    var panelFrame: CGRect? { get }
    func show(near icon: CGRect, edge: DockEdge, screenFrame: CGRect)
    func hide()
}

/// Non-activating floating panel: never key, never main, so hovering or clicking it keeps the keyboard where it was.
final class PreviewNSPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PreviewPanelPresenter: PreviewPresenting {
    private let panel: PreviewNSPanel
    private let host: NSHostingView<PreviewView>

    init(model: PreviewModel) {
        panel = PreviewNSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar // above the Dock window level
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        host = NSHostingView(rootView: PreviewView(model: model))
        panel.contentView = host
    }

    var panelFrame: CGRect? { panel.isVisible ? panel.frame : nil }

    func show(near icon: CGRect, edge: DockEdge, screenFrame: CGRect) {
        let size = host.fittingSize
        panel.setFrame(DockGeometry.previewFrame(icon: icon, size: size, edge: edge, screenFrame: screenFrame, gap: 8),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}
