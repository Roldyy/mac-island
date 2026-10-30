import AppKit
import SwiftUI

/// Borderless panel that floats over the menu bar. It takes the keyboard only when asked
/// (click in a text field or the terminal), so hovering never steals focus from the frontmost app.
public final class NotchPanel: NSPanel {
    public var acceptsKeyboard = false

    public override var canBecomeKey: Bool { acceptsKeyboard }
    public override var canBecomeMain: Bool { false }

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

/// Owns the panel, follows hover, and animates between the idle notch and the open island.
@MainActor
public final class IslandController {
    public let panel = NotchPanel()
    public var openSize = CGSize(width: 640, height: 360)

    private let screen: NSScreen
    private var tracking: NSTrackingArea?
    private var isOpen = false
    private var closeWork: DispatchWorkItem?

    public let state = IslandState()
    private lazy var hoverTarget = HoverTarget(controller: self)

    /// `content` reads `IslandState` from the environment to know whether the island is open.
    public init<Content: View>(screen: NSScreen? = nil, @ViewBuilder content: () -> Content) {
        self.screen = screen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens[0]
        panel.contentView = NSHostingView(
            rootView: content().environmentObject(state))
        panel.setFrame(idleGeometry.frame, display: false)
    }

    private var idleGeometry: NotchGeometry {
        NotchGeometry.idle(
            screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea)
    }

    public func show() {
        panel.orderFrontRegardless()
        installTracking()
    }

    public func open() {
        closeWork?.cancel()
        guard !isOpen else { return }
        isOpen = true
        state.isOpen = true
        let target = NotchGeometry.expanded(from: idleGeometry, size: openSize, screenFrame: screen.frame)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
        installTracking()
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        state.isOpen = false
        panel.acceptsKeyboard = false
        panel.resignKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(idleGeometry.frame, display: true)
        }
        installTracking()
    }

    /// Called by content that needs typing (note, search, terminal) after a click.
    public func focusKeyboard() {
        panel.acceptsKeyboard = true
        panel.makeKey()
    }

    // MARK: - Hover

    private func installTracking() {
        guard let view = panel.contentView else { return }
        if let tracking { view.removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: hoverTarget, userInfo: nil)
        view.addTrackingArea(area)
        tracking = area
    }

    fileprivate func hoverChanged(inside: Bool) {
        closeWork?.cancel()
        if inside {
            open()
        } else {
            // Short grace period so the island does not flicker when the pointer grazes the edge.
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.close() }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }
}

/// Observable flag shared with the SwiftUI content.
@MainActor
public final class IslandState: ObservableObject {
    @Published public var isOpen = false
}

private final class HoverTarget: NSObject {
    weak var controller: IslandController?
    init(controller: IslandController) { self.controller = controller }

    @objc func mouseEntered(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.hoverChanged(inside: true) }
    }

    @objc func mouseExited(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.hoverChanged(inside: false) }
    }
}
