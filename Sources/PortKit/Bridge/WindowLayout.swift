// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W3B (layout and maximize). The lane owns this file.

import AppKit
import SwiftUI

// MARK: - Visibility clamp

/// Keeps a window the lane places (or restores) inside the screens that exist NOW. A remembered frame can belong to
/// a display that was unplugged, moved or resized since: writing it back verbatim would leave the window where no
/// pointer can reach its title bar. All rects here are AppKit rects (origin bottom-left, y up), which is what
/// `NSScreen.visibleFrame` uses: menu bar and Dock are already out of every visible frame.
enum WindowLayoutVisibility {
    /// How much of the window must lie on a screen for it to count as reachable: a title bar's worth.
    static let minimumGrab = CGSize(width: 120, height: 60)

    /// The visible frame that holds most of the rect, or, when none touches it, the nearest one by centre.
    static func bestFrame(for rect: CGRect, in frames: [CGRect]) -> CGRect? {
        let usable = frames.filter { !$0.isNull && !$0.isEmpty && $0.width > 0 && $0.height > 0 }
        guard !usable.isEmpty else { return nil }
        func overlap(_ frame: CGRect) -> CGFloat {
            let shared = frame.intersection(rect)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        if let best = usable.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 { return best }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        func distance(_ frame: CGRect) -> CGFloat {
            hypot(frame.midX - centre.x, frame.midY - centre.y)
        }
        return usable.min(by: { distance($0) < distance($1) })
    }

    /// True when a grabbable part of the window is on a screen, with its top edge not above that screen's visible
    /// frame (the title bar is under the menu bar, never behind it).
    static func isReachable(_ rect: CGRect, in frames: [CGRect]) -> Bool {
        guard rect.width > 0, rect.height > 0, let frame = bestFrame(for: rect, in: frames) else { return false }
        let shared = frame.intersection(rect)
        guard !shared.isNull else { return false }
        return shared.width >= min(rect.width, minimumGrab.width)
            && shared.height >= min(rect.height, minimumGrab.height)
            && rect.maxY <= frame.maxY + 0.5
    }

    /// The rect unchanged when it is already reachable (a window the person left half off a screen on purpose stays
    /// where it is). Otherwise it shrinks to fit the best visible frame and moves fully inside it. No visible
    /// frame at all (a transient state during a display change) leaves the rect alone.
    static func clamped(_ rect: CGRect, toVisibleFrames frames: [CGRect]) -> CGRect {
        guard rect.width > 0, rect.height > 0, let frame = bestFrame(for: rect, in: frames) else { return rect }
        if isReachable(rect, in: frames) { return rect }
        let width = min(rect.width, frame.width)
        let height = min(rect.height, frame.height)
        let x = min(max(rect.minX, frame.minX), frame.maxX - width)
        let y = min(max(rect.minY, frame.minY), frame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}

// MARK: - Display watch

/// Tells the layout service when the display arrangement changes, for as long as the feature runs. Installed on
/// start and removed on stop (both idempotent); the live watcher is a main-queue notification observer, no thread.
@MainActor
final class WindowLayoutDisplayWatch {
    typealias Install = (@escaping @MainActor () -> Void) -> () -> Void

    private let install: Install
    private let onChange: @MainActor () -> Void
    private var remove: (() -> Void)?

    var isWatching: Bool { remove != nil }

    init(install: @escaping Install, onChange: @escaping @MainActor () -> Void) {
        self.install = install
        self.onChange = onChange
    }

    func begin() {
        guard remove == nil else { return }
        remove = install(onChange)
    }

    func end() {
        remove?()
        remove = nil
    }

    static let liveInstall: Install = { handler in
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return { NotificationCenter.default.removeObserver(token) }
    }
}

// MARK: - The lane

/// Binds this lane's two ported features. Called once at launch by `PortLanes`, before the registry exists.
///
/// - `windowLayout` (page 32, "Disposition des fenêtres"): halves, thirds, quarters, sixths, corners, maximize,
///   centre, display moves, restore; shortcuts (Carbon hot keys), the pointer layout, the drag-to-edge snapping
///   with its preview HUD and the move and resize gestures (head taps on the main run loop), the next-display
///   pointer key. Start is `WindowLayoutService.syncWithPreferences()`, which arms each input only when its own
///   page toggle, the registry's verdict (`AppFeature.windowLayout.isAvailable`), Accessibility and an active
///   session all agree. Stop is `suspend()` plus the pointer key's `suspend()`: every hot key, tap, timer and
///   observer goes down whatever the preferences say.
/// - `windowMaximizer` (page 33, "Maximiser les fenêtres"): the green button zooms inside the current Space.
///   Start is `WindowMaximizer.syncWithPreferences()`, stop is `stop()` (tap removed, animations cancelled, the
///   assistive flag handed back).
///
/// Both features need Accessibility: the binding refuses to start either without it and never prompts; the
/// registry restarts them when the monitor sees the grant. A system that disables a tap is handled upstream (the
/// tap callbacks re-enable it, or re-sync, which removes it). The shortcuts of `windowLayout` are owned by it alone:
/// `PortShortcutOwnership.isRunning(.windowLayout)` is what the central shortcuts page and the recorders read.
/// The gestures read `com.apple.WindowManager`, `com.apple.spaces` and `com.apple.dock` preferences, read-only.
enum WindowLayoutLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        var syncLayout: @MainActor () -> Void
        var suspendLayout: @MainActor () -> Void
        var suspendPointerKey: @MainActor () -> Void
        var displaysChanged: @MainActor () -> Void
        var installDisplayWatch: WindowLayoutDisplayWatch.Install
        var syncMaximizer: @MainActor () -> Void
        var stopMaximizer: @MainActor () -> Void

        static let live = Runtime(
            syncLayout: { WindowLayoutService.shared.syncWithPreferences() },
            suspendLayout: { WindowLayoutService.shared.suspend() },
            suspendPointerKey: { PointerDisplayService.shared.suspend() },
            displaysChanged: { WindowLayoutService.shared.displaysChanged() },
            installDisplayWatch: WindowLayoutDisplayWatch.liveInstall,
            syncMaximizer: { WindowMaximizer.shared.syncWithPreferences() },
            stopMaximizer: { WindowMaximizer.shared.stop() })
    }

    static let layoutPageID = "windowlayout"
    static let maximizerPageID = "maximize"
    static let featureIDs = ["windowLayout", "windowMaximizer"]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        let watch = WindowLayoutDisplayWatch(install: runtime.installDisplayWatch,
                                             onChange: runtime.displaysChanged)
        binding.bind(
            "windowLayout",
            page: PortFeaturePage(pageID: layoutPageID) { AnyView(WindowLayoutSettings(parts: [.layout])) },
            start: {
                watch.begin()
                runtime.syncLayout()
            },
            stop: {
                watch.end()
                runtime.suspendLayout()
                runtime.suspendPointerKey()
            })
        binding.bind(
            "windowMaximizer",
            page: PortFeaturePage(pageID: maximizerPageID) { AnyView(WindowLayoutSettings(parts: [.maximizer])) },
            start: { runtime.syncMaximizer() },
            stop: { runtime.stopMaximizer() })
    }
}
