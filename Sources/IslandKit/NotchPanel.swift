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

/// How the panel frame follows a size change without being resized every frame: it grows at once (to the
/// union of the old and new frames, both are top-centred) and shrinks only after SwiftUI has finished
/// animating the shape inside it. The window server never sees an animated frame.
public struct IslandFramePlan: Equatable, Sendable {
    /// Set right away.
    public let immediate: CGRect
    /// Set `IslandRevealCurve.settleDelay` later, when the shape no longer needs the room. Nil when none.
    public let settled: CGRect?

    public static func make(current: CGRect, target: CGRect, animated: Bool) -> IslandFramePlan {
        guard animated, current != target, !current.isEmpty else {
            return IslandFramePlan(immediate: target, settled: nil)
        }
        let union = current.union(target)
        return IslandFramePlan(immediate: union, settled: union == target ? nil : target)
    }
}

/// Owns the panel, follows hover, and opens or closes the island.
///
/// Open and close are one SwiftUI animation on a single progress value (`IslandRevealCurve`); the panel frame
/// is set once per transition, never animated. The content is built once and kept alive.
@MainActor
public final class IslandController {
    public let panel = NotchPanel()
    public var openSize = CGSize(width: 640, height: 360)

    private var screen: NSScreen
    private let followsScreenChanges: Bool
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isShown = false
    private var isOpen = false
    private var closeWork: DispatchWorkItem?
    private var settleTask: Task<Void, Never>?
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
        let host = NSHostingView(
            rootView: NotchBackdrop(content: content()).environmentObject(state).environment(\.islandActions, actions))
        // The panel is sized by the controller only: no min/max/intrinsic size feedback from the content.
        host.sizingOptions = []
        panel.contentView = host
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
            // A Space switch, a display waking from sleep or a fullscreen app can leave the panel unordered or
            // on a stale frame without any screen-parameter notification: put it back each time.
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                         NSWorkspace.screensDidWakeNotification] {
                workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.screensChanged() }
                })
            }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Screens, Spaces or sleep changed: pick the screen again, put the panel on its frame and keep it ordered
    /// front. The closed island is always on screen, so nothing here may leave the panel hidden.
    private func screensChanged() {
        screen = Self.preferredScreen()
        updateNotchMetrics()
        let frame = isOpen
            ? NotchGeometry.expanded(from: idleGeometry, size: openSize, screenFrame: screen.frame)
            : closedFrame
        move(to: frame, animated: false)
        pointerInside = false
        if isShown { panel.orderFrontRegardless() }
        NSLog("IslandKit: screens changed, now on %@ (notch=%d) visible=%d", screen.localizedName,
              idleGeometry.hasNotch ? 1 : 0, panel.isVisible ? 1 : 0)
    }

    /// The notch pill with its base wings, widened by the wings of the current layout and by nothing else.
    private var closedFrame: CGRect {
        NotchGeometry.closedFrame(
            from: idleGeometry, wingExtent: NotchGeometry.wingExtent(for: layout), screenFrame: screen.frame)
    }

    private func updateNotchMetrics() {
        state.notchWidth = idleGeometry.frame.width
        state.notchHeight = idleGeometry.frame.height
        updateClosedMetrics()
    }

    /// The closed strip is drawn at this fixed size inside the (possibly larger) panel.
    private func updateClosedMetrics() {
        let size = closedFrame.size
        if state.closedWidth != size.width { state.closedWidth = size.width }
        if state.closedHeight != size.height { state.closedHeight = size.height }
    }

    private func layoutChanged(_ new: ActivityLayout) {
        guard new != layout else { return }
        layout = new
        updateClosedMetrics()
        if !isOpen { move(to: closedFrame) }
    }

    /// Frame change without a per-frame resize: grow now, shrink once the SwiftUI animation is over.
    /// Instant when the user asked for Reduce Motion.
    private func move(to frame: CGRect, animated: Bool = true) {
        settleTask?.cancel()
        settleTask = nil
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let plan = IslandFramePlan.make(current: panel.frame, target: frame, animated: animated && !reduce)
        if panel.frame != plan.immediate { panel.setFrame(plan.immediate, display: true) }
        guard let settled = plan.settled else { return }
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(IslandRevealCurve.settleDelay))
            guard !Task.isCancelled, let self else { return }
            self.panel.setFrame(settled, display: true)
            self.settleTask = nil
        }
    }

    /// Each tab may ask for its own open height; the width stays the shell's.
    public func setOpenHeight(_ height: CGFloat) {
        openSize.height = NotchGeometry.clampedOpenHeight(height, screenFrame: screen.frame)
        guard isOpen else { return }
        move(to: NotchGeometry.expanded(from: idleGeometry, size: openSize, screenFrame: screen.frame))
    }
    private var monitors: [Any] = []

    private var idleGeometry: NotchGeometry {
        NotchGeometry.idle(
            screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea)
    }

    public func show() {
        isShown = true
        HitchProbe.shared.startIfRequested()  // only with MIS_HITCH_LOG set; nothing is installed otherwise
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
        // Panel first (at its final size, at once), then the one animation that reveals the content inside it.
        move(to: NotchGeometry.expanded(from: idleGeometry, size: openSize, screenFrame: screen.frame))
        state.isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        state.isOpen = false
        panel.acceptsKeyboard = false
        panel.resignKey()
        move(to: closedFrame)
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
    /// Size of the closed island (notch plus wings). The panel can be larger while it opens or closes.
    @Published public var closedWidth: CGFloat = NotchGeometry.pillWidth
    @Published public var closedHeight: CGFloat = NotchGeometry.pillHeight
}

