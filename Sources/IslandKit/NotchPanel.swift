import AppKit
import Combine
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
        // The island is always dark (it merges with the black notch): dark tokens and materials even in a
        // light system appearance. Only the Settings window follows the system and uses the light tokens.
        appearance = NSAppearance(named: .darkAqua)
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
    private var layout = ActivityLayout.empty
    private var layoutSubscription: AnyCancellable?

    public let state = IslandState()

    /// The built-in notched screen when it is active, otherwise the main screen.
    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// `content` reads `IslandState` from the environment to know whether the island is open.
    public init<Content: View>(
        screen: NSScreen? = nil, activityCenter: ActivityCenter? = nil, @ViewBuilder content: () -> Content
    ) {
        self.screen = screen ?? Self.preferredScreen()
        self.followsScreenChanges = screen == nil
        let actions = IslandActions(
            focusKeyboard: { [weak self] in self?.focusKeyboard() },
            close: { [weak self] in self?.close() })
        panel.contentView = NSHostingView(
            rootView: NotchBackdrop(content: content()).environmentObject(state).environment(\.islandActions, actions))
        updateNotchMetrics()
        panel.setFrame(closedFrame, display: false)
        // Receives the current layout at once, then every change.
        layoutSubscription = (activityCenter ?? .shared).$layout.sink { [weak self] layout in
            MainActor.assumeIsolated { self?.layoutChanged(layout) }
        }
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
            : closedFrame
        updateNotchMetrics()
        panel.setFrame(frame, display: true)
        pointerInside = false
        NSLog("IslandKit: screens changed, now on %@ (notch=%d)", screen.localizedName,
              idleGeometry.hasNotch ? 1 : 0)
    }

    /// The notch pill with its base wings, widened by the wings of the current layout and by nothing else.
    private var closedFrame: CGRect {
        NotchGeometry.closedFrame(
            from: idleGeometry, wingExtent: NotchGeometry.wingExtent(for: layout), screenFrame: screen.frame)
    }

    private func updateNotchMetrics() {
        state.notchWidth = idleGeometry.frame.width
        state.notchHeight = idleGeometry.frame.height
    }

    private func layoutChanged(_ new: ActivityLayout) {
        guard new != layout else { return }
        layout = new
        if !isOpen { move(to: closedFrame, duration: 0.2, curve: .easeOut) }
    }

    /// Animated frame change, instant when the user asked for Reduce Motion.
    private func move(to frame: CGRect, duration: TimeInterval, curve: CAMediaTimingFunctionName) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: curve)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Each tab may ask for its own open height; the width stays the shell's.
    public func setOpenHeight(_ height: CGFloat) {
        openSize.height = NotchGeometry.clampedOpenHeight(height, screenFrame: screen.frame)
        guard isOpen else { return }
        move(to: NotchGeometry.expanded(from: idleGeometry, size: openSize, screenFrame: screen.frame),
             duration: 0.18, curve: .easeOut)
    }
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
        move(to: target, duration: 0.18, curve: .easeOut)
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        state.isOpen = false
        panel.acceptsKeyboard = false
        panel.resignKey()
        move(to: closedFrame, duration: 0.16, curve: .easeIn)
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
        var zone = isOpen ? panel.frame : closedFrame
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
    /// Hardware notch (or pill) size, so content can leave the gap clear and the backdrop can fill it.
    @Published public var notchWidth: CGFloat = NotchGeometry.pillWidth
    @Published public var notchHeight: CGFloat = NotchGeometry.pillHeight
}

