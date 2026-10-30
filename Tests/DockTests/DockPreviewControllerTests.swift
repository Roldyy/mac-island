import CoreGraphics
import Foundation
import Testing
@testable import DockFeature

@MainActor final class FakePresenter: PreviewPresenting {
    var panelFrame: CGRect?
    var shows = 0
    var hides = 0
    func show(near icon: CGRect, edge: DockEdge, screenFrame: CGRect) { shows += 1; panelFrame = CGRect(x: 500, y: 80, width: 300, height: 100) }
    func hide() { hides += 1; panelFrame = nil }
}

@MainActor final class FakePermissions: DockPermissionChecking {
    var accessibilityGranted = true
    var screenRecordingGranted = false
    var screenRequests = 0
    func requestAccessibility() {}
    func requestScreenRecording() { screenRequests += 1 }
}

struct NoCapture: WindowCapturing {
    func thumbnails(pid: Int32, frames: [CGRect], maxSize: CGSize) async -> [CGImage?] { frames.map { _ in nil } }
}

@MainActor @Suite final class DockPreviewControllerTests {
    let resolver = FakeResolver()
    let windows = FakeWindows()
    let presenter = FakePresenter()
    let permissions = FakePermissions()
    let model = PreviewModel()
    let clock = Box()
    final class Box { var t = 0.0 }
    /// Released with the suite instance: removes the suite's preference domain after the test.
    private let temp = TempDefaults(prefix: "dock-prev")

    func make() -> DockPreviewController {
        let d = temp.defaults
        d.set(true, forKey: "dockPreviewEnabled")
        d.set(400, forKey: "dockPreviewDelayMilliseconds")
        let c = clock
        return DockPreviewController(
            settings: { DockSettings(defaults: d) }, resolver: resolver, windows: windows, capturer: NoCapture(),
            permissions: permissions, presenter: presenter, model: model,
            screens: { [.init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                              visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 800))] },
            clock: { c.t })
    }
    let app = DockApp(bundleID: "com.a", pid: 7, iconFrame: CGRect(x: 700, y: 4, width: 56, height: 56))
    let onIcon = CGPoint(x: 720, y: 30)

    @Test func showsAfterTheDelayWithTitlesOnlyWithoutScreenRecording() {
        resolver.app = app
        windows.windows = [DockWindow(title: "One"), DockWindow(title: "Two")]
        let c = make()
        c.pointerMoved(onIcon)
        #expect(presenter.shows == 0)
        clock.t = 0.5
        c.tick()
        #expect(presenter.shows == 1)
        #expect(model.items.map(\.title) == ["One", "Two"])
        #expect(model.needsScreenRecording)
        #expect(model.items.allSatisfy { $0.thumbnail == nil })
    }
    @Test func appWithoutWindowsShowsNothing() {
        resolver.app = app
        windows.windows = []
        let c = make()
        c.pointerMoved(onIcon); clock.t = 0.5; c.tick()
        #expect(presenter.shows == 0)
    }
    @Test func pointerOutsideTheDockStripNeverAsksAccessibility() {
        resolver.app = app
        let c = make()
        c.pointerMoved(CGPoint(x: 720, y: 400))
        #expect(resolver.calls == 0)
    }
    @Test func hidesAfterGraceAndReleasesTheItems() {
        resolver.app = app
        windows.windows = [DockWindow(title: "One")]
        let c = make()
        c.pointerMoved(onIcon); clock.t = 0.5; c.tick()
        resolver.app = nil
        c.pointerMoved(CGPoint(x: 100, y: 400)); clock.t = 0.6; c.tick()
        #expect(presenter.hides == 0)
        clock.t = 1.0; c.tick()
        #expect(presenter.hides == 1)
        #expect(model.items.isEmpty)
    }
    @Test func requestingScreenRecordingOnlyHappensOnTheButton() {
        resolver.app = app
        windows.windows = [DockWindow()]
        let c = make()
        c.pointerMoved(onIcon); clock.t = 0.5; c.tick()
        #expect(permissions.screenRequests == 0)
        model.onRequestScreenRecording()
        #expect(permissions.screenRequests == 1)
    }
    @Test func raiseGoesToTheWindowServiceAndClosesThePreview() {
        resolver.app = app
        windows.windows = [DockWindow(), DockWindow()]
        let c = make()
        c.pointerMoved(onIcon); clock.t = 0.5; c.tick()
        model.onRaise(1)
        #expect(windows.raised.count == 1 && windows.raised[0].0 == 7 && windows.raised[0].1 == 1)
        #expect(presenter.hides == 1)
    }
}
