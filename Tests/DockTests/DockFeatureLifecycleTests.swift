import CoreGraphics
import Testing
@testable import DockFeature

@MainActor final class FakeMouseSource: MouseEventSource {
    var startCount = 0
    var stopCount = 0
    var isRunning = false
    var handler: ((MouseEvent) -> Void)?
    func start(_ handler: @escaping (MouseEvent) -> Void) {
        startCount += 1; isRunning = true; self.handler = handler
    }
    func stop() { stopCount += 1; isRunning = false; handler = nil }
}

@MainActor @Suite struct DockFeatureLifecycleTests {
    @Test func startAndStopAreIdempotent() {
        let source = FakeMouseSource()
        let c = DockCoordinator(source: source, click: nil, preview: nil)
        c.start(); c.start()
        #expect(source.startCount == 1 && c.isStarted)
        c.stop(); c.stop()
        #expect(source.stopCount == 1 && !c.isStarted)
        c.start()
        #expect(source.startCount == 2)
    }
    @Test func stopBeforeStartIsANoOp() {
        let source = FakeMouseSource()
        let c = DockCoordinator(source: source, click: nil, preview: nil)
        c.stop()
        #expect(source.stopCount == 0)
    }
}

@MainActor @Suite struct DockCoordinatorClickRoutingTests {
    let source = FakeMouseSource()
    let resolver = FakeResolver()
    let windows = FakeWindows()
    let workspace = FakeWorkspace()
    let scheduler = FakeScheduler()
    let app = DockApp(bundleID: "com.a", pid: 42, iconFrame: .zero)

    func start() -> DockCoordinator {
        let s = scheduler
        resolver.app = app; workspace.frontmost = "com.a"; windows.windows = [DockWindow()]
        let click = DockClickController(options: { DockClickOptions(minimize: true, hide: false, cycle: false) },
                                        resolver: resolver, windows: windows, workspace: workspace,
                                        schedule: { s.schedule($0, $1) })
        let c = DockCoordinator(source: source, click: click, preview: nil)
        c.start()
        return c
    }

    @Test func downThenUpActsOnlyAfterTheDelay() {
        let c = start()
        source.handler?(.down(.zero))
        #expect(windows.performed.isEmpty)
        source.handler?(.up(.zero))
        #expect(windows.performed.isEmpty)
        scheduler.fire()
        #expect(windows.performed.count == 1)
        #expect(c.isStarted)
    }
    @Test func aDragBetweenDownAndUpCancels() {
        let c = start()
        source.handler?(.down(.zero))
        source.handler?(.dragged(CGPoint(x: 40, y: 0)))
        source.handler?(.up(CGPoint(x: 40, y: 0)))
        scheduler.fire()
        #expect(windows.performed.isEmpty)
        #expect(c.isStarted)   // the coordinator was alive for the whole sequence
    }
    @Test func stopCancelsAPendingAction() {
        let c = start()
        source.handler?(.down(.zero))
        source.handler?(.up(.zero))
        c.stop()
        scheduler.fire()
        #expect(windows.performed.isEmpty)
    }
}
