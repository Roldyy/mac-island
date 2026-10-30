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
        // Above the menu bar and above other notch overlays (Vorssaint, Glasswave) while they coexist.
        level = .screenSaver
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

    private var screen: NSScreen
    private let followsScreenChanges: Bool
    private var screenObserver: NSObjectProtocol?
    private var isOpen = false
    private var closeWork: DispatchWorkItem?

    public let state = IslandState()

    /// The built-in notched screen when it is active, otherwise the main screen.
    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// `content` reads `IslandState` from the environment to know whether the island is open.
    public init<Content: View>(screen: NSScreen? = nil, @ViewBuilder content: () -> Content) {
        self.screen = screen ?? Self.preferredScreen()
        self.followsScreenChanges = screen == nil
        let actions = IslandActions(
            focusKeyboard: { [weak self] in self?.focusKeyboard() },
            close: { [weak self] in self?.close() })
        panel.contentView = NSHostingView(
            rootView: content().environmentObject(state).environment(\.islandActions, actions))
        panel.setFrame(idleFrame, display: false)
        if followsScreenChanges {
            // Lid closed or opened, a display plugged in or removed, a new primary display.
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func screensChanged() {
        screen = Self.preferredScreen()
        let frame = isOpen
            ? NotchGeometry.expanded(from: idleGeometry, size: openSize, screenFrame: screen.frame)
            : idleFrame
        panel.setFrame(frame, display: true)
        pointerInside = false
        NSLog("IslandKit: screens changed, now on %@ (notch=%d)", screen.localizedName,
              idleGeometry.hasNotch ? 1 : 0)
    }

    /// Visible "wings" on each side of the notch: the notch itself has no pixels to draw on.
    private let wing: CGFloat = 16
    private var idleFrame: CGRect { idleGeometry.frame.insetBy(dx: -wing, dy: 0) }
    private var monitors: [Any] = []

    private var idleGeometry: NotchGeometry {
        NotchGeometry.idle(
            screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea)
    }

    public func show() {
        panel.orderFrontRegardless()
        installHoverMonitors()
        let g = idleGeometry
        NSLog("IslandKit: screen=%@ frame=%@ safeTop=%f hasNotch=%d idle=%@ panelFrame=%@ visible=%d level=%d",
              screen.localizedName, NSStringFromRect(screen.frame), screen.safeAreaInsets.top,
              g.hasNotch ? 1 : 0, NSStringFromRect(g.frame), NSStringFromRect(panel.frame),
              panel.isVisible ? 1 : 0, panel.level.rawValue)
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
            panel.animator().setFrame(idleFrame, display: true)
        }
    }

    /// Called by content that needs typing (note, search, terminal) after a click.
    public func focusKeyboard() {
        panel.acceptsKeyboard = true
        panel.makeKey()
    }

    // MARK: - Hover

    /// Mouse position is read globally: it keeps working when another window sits on top of the
    /// island and it does not depend on the notch area receiving events.
    private func installHoverMonitors() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private var pointerInside = false

    private func pointerMoved() {
        // Open: stay open over the whole panel. Closed: react to the wings and the notch strip.
        var zone = isOpen ? panel.frame : idleFrame
        zone.size.height += 2  // reach the very top edge, where the pointer stops
        let inside = zone.contains(NSEvent.mouseLocation)
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverChanged(inside: inside)
    }

    fileprivate func hoverChanged(inside: Bool) {
        NSLog("IslandKit: hover %@", inside ? "enter" : "exit")
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

