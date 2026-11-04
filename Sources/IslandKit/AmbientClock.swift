import AppKit
import Combine

/// The one place the closed strip's animations ask "may I run?". It publishes a single flag, so a pause or a
/// resume redraws the few animated views once, and nothing here emits while the strip is hidden: the views
/// hand a paused `TimelineView` (or a static text) to SwiftUI instead of a display link.
///
/// The controller feeds it the two facts only it knows (island open, panel occlusion); the clock watches the
/// rest itself (screen sleep, session lock). A freshly created clock says "visible", so previews and tests
/// that never attach a panel still draw.
@MainActor
public final class AmbientClock: ObservableObject {
    public static let shared = AmbientClock()

    @Published public private(set) var inputs = AmbientClockInputs()
    @Published public private(set) var isVisible = true

    private var observers: [NSObjectProtocol] = []
    private var occlusionObserver: NSObjectProtocol?

    public init(observeSystem: Bool = true) {
        guard observeSystem else { return }
        let center = NSWorkspace.shared.notificationCenter
        let asleep: [NSNotification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification]
        let awake: [NSNotification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification]
        for name in asleep { observe(name, on: center) { $0.screenAsleep = true } }
        for name in awake { observe(name, on: center) { $0.screenAsleep = false } }
        observe(NSWorkspace.sessionDidResignActiveNotification, on: center) { $0.sessionActive = false }
        observe(NSWorkspace.sessionDidBecomeActiveNotification, on: center) { $0.sessionActive = true }
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    private func observe(_ name: NSNotification.Name, on center: NotificationCenter, _ change: @escaping (inout AmbientClockInputs) -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(change) }
        })
    }

    public func update(_ change: (inout AmbientClockInputs) -> Void) {
        var next = inputs
        change(&next)
        guard next != inputs else { return }
        inputs = next
        let visible = AmbientClockPolicy.stripIsVisible(next)
        if visible != isVisible { isVisible = visible }
    }

    public func setIslandOpen(_ open: Bool) { update { $0.islandOpen = open } }

    /// Follows the panel's occlusion state (covered, screen off, another Space) until the next `follow`.
    public func follow(_ window: NSWindow) {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        update { $0.panelOccluded = !window.occlusionState.contains(.visible) }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                self?.update { $0.panelOccluded = !window.occlusionState.contains(.visible) }
            }
        }
    }
}
