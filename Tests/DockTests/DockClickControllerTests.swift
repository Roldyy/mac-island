import CoreGraphics
import Foundation
import Testing
@testable import DockFeature

/// Ordered record of what happened, shared by the fakes so a test can assert the order.
@MainActor final class EventLog {
    var entries: [String] = []
}

@MainActor final class FakeResolver: DockItemResolving {
    var app: DockApp?
    var calls = 0
    func app(at point: CGPoint) -> DockApp? { calls += 1; return app }
}

@MainActor final class FakeWindows: AppWindowAccessing {
    var windows: [DockWindow] = []
    var performed: [(DockClickAction, Int32)] = []
    var raised: [(Int32, Int)] = []
    var log: EventLog?
    func windows(pid: Int32) -> [DockWindow] { windows }
    func perform(_ action: DockClickAction, pid: Int32) {
        performed.append((action, pid)); log?.entries.append("perform \(action)")
    }
    func raise(pid: Int32, windowAt index: Int) { raised.append((pid, index)) }
}

@MainActor final class FakeWorkspace: WorkspaceQuerying {
    var frontmost: String?
    var hidden = false
    var frontmostBundleID: String? { frontmost }
    func isHidden(pid: Int32) -> Bool { hidden }
}

/// Holds scheduled work until the test fires it, like the main queue would after the delay.
@MainActor final class FakeScheduler {
    struct Job { var delay: TimeInterval; var work: @MainActor () -> Void; var cancelled = false }
    private(set) var jobs: [Job] = []
    var pending: Int { jobs.filter { !$0.cancelled }.count }
    var delays: [TimeInterval] { jobs.map(\.delay) }
    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        jobs.append(Job(delay: delay, work: work))
        let index = jobs.count - 1
        return { MainActor.assumeIsolated { self.jobs[index].cancelled = true } }
    }
    func fire() {
        for i in jobs.indices where !jobs[i].cancelled {
            jobs[i].cancelled = true
            jobs[i].work()
        }
    }
}

@MainActor @Suite struct DockClickControllerTests {
    let resolver = FakeResolver()
    let windows = FakeWindows()
    let workspace = FakeWorkspace()
    let scheduler = FakeScheduler()
    let log = EventLog()

    init() { windows.log = log }

    func make(_ o: DockClickOptions = DockClickOptions(minimize: true, hide: false, cycle: true)) -> DockClickController {
        let s = scheduler
        return DockClickController(options: { o }, resolver: resolver, windows: windows, workspace: workspace,
                                   schedule: { s.schedule($0, $1) })
    }
    let app = DockApp(bundleID: "com.a", pid: 42, iconFrame: .zero)
    let other = DockApp(bundleID: "com.b", pid: 43, iconFrame: .zero)

    func armFrontmostClick() {
        resolver.app = app; workspace.frontmost = "com.a"; windows.windows = [DockWindow()]
    }

    @Test func frontmostClickMinimizesOnlyAfterMouseUpAndTheDelay() {
        armFrontmostClick()
        let c = make()
        #expect(c.handleMouseDown(at: .zero) == .minimizeAll)
        #expect(windows.performed.isEmpty)               // mouse-down decides, never acts
        c.handleMouseUp(at: .zero)
        log.entries.append("dock handles the click")     // the Dock acts on mouse-up too
        #expect(windows.performed.isEmpty)
        #expect(scheduler.pending == 1)
        #expect(scheduler.delays == [DockClickController.actDelay])
        #expect(DockClickController.actDelay >= 0.1)
        scheduler.fire()
        #expect(windows.performed.count == 1 && windows.performed[0].1 == 42)
        // The ordering that matters: our action lands after the Dock's own handling, not before it.
        #expect(log.entries == ["dock handles the click", "perform minimizeAll"])
    }
    @Test func clickOffTheDockDoesNotTouchWindows() {
        resolver.app = nil
        let c = make()
        #expect(c.handleMouseDown(at: .zero) == .none)
        c.handleMouseUp(at: .zero)
        scheduler.fire()
        #expect(windows.performed.isEmpty && scheduler.jobs.isEmpty)
    }
    @Test func allOptionsOffSkipsTheAccessibilityLookup() {
        resolver.app = app
        _ = make(DockClickOptions(minimize: false, hide: false, cycle: false)).handleMouseDown(at: .zero)
        #expect(resolver.calls == 0)
    }
    @Test func nothingDecisionSchedulesNothing() {
        resolver.app = app; workspace.frontmost = "com.b"; windows.windows = [DockWindow()]
        let c = make()
        #expect(c.handleMouseDown(at: .zero) == .none)
        c.handleMouseUp(at: .zero)
        scheduler.fire()
        #expect(windows.performed.isEmpty && scheduler.jobs.isEmpty)
    }
    @Test func hiddenAppIsNotTouched() {
        resolver.app = app; workspace.frontmost = "com.a"; workspace.hidden = true; windows.windows = [DockWindow()]
        #expect(make().handleMouseDown(at: .zero) == .none)
    }
    @Test func mouseUpWithoutAMouseDownDoesNothing() {
        armFrontmostClick()
        make().handleMouseUp(at: .zero)
        scheduler.fire()
        #expect(windows.performed.isEmpty && scheduler.jobs.isEmpty)
    }
    @Test func pointerThatLeftTheIconCancels() {
        armFrontmostClick()
        let c = make()
        _ = c.handleMouseDown(at: .zero)
        resolver.app = nil                                // released away from any Dock icon
        c.handleMouseUp(at: CGPoint(x: 500, y: 500))
        scheduler.fire()
        #expect(windows.performed.isEmpty && scheduler.jobs.isEmpty)
    }
    @Test func releaseOverAnotherAppCancels() {
        armFrontmostClick()
        let c = make()
        _ = c.handleMouseDown(at: .zero)
        resolver.app = other
        c.handleMouseUp(at: CGPoint(x: 90, y: 0))
        scheduler.fire()
        #expect(windows.performed.isEmpty)
    }
    @Test func aDragCancels() {
        armFrontmostClick()
        let c = make()
        _ = c.handleMouseDown(at: .zero)
        c.cancelPending()                                 // the coordinator calls this on a drag
        c.handleMouseUp(at: .zero)
        scheduler.fire()
        #expect(windows.performed.isEmpty)
    }
    @Test func cancellingAfterTheMouseUpCancelsTheScheduledWork() {
        armFrontmostClick()
        let c = make()
        _ = c.handleMouseDown(at: .zero)
        c.handleMouseUp(at: .zero)
        #expect(scheduler.pending == 1)
        c.cancelPending()
        #expect(scheduler.pending == 0)
        scheduler.fire()
        #expect(windows.performed.isEmpty)
    }
    @Test func frontmostAppChangingBeforeTheActionCancelsIt() {
        armFrontmostClick()
        let c = make()
        _ = c.handleMouseDown(at: .zero)
        c.handleMouseUp(at: .zero)
        workspace.frontmost = "com.b"                     // Cmd+Tab or the Dock switched apps meanwhile
        scheduler.fire()
        #expect(windows.performed.isEmpty)
    }
    @Test func aNewMouseDownReplacesThePendingAction() {
        armFrontmostClick()
        let c = make()
        _ = c.handleMouseDown(at: .zero)
        c.handleMouseUp(at: .zero)
        _ = c.handleMouseDown(at: .zero)
        #expect(scheduler.pending == 0)                   // the first job was cancelled
        c.handleMouseUp(at: .zero)
        scheduler.fire()
        #expect(windows.performed.count == 1)
    }
    @Test func restoreAllDoesNotNeedTheAppToBeFrontmostWhenItFires() {
        resolver.app = app; workspace.frontmost = "com.z"
        windows.windows = [DockWindow(isMinimized: true)]
        let c = make()
        #expect(c.handleMouseDown(at: .zero) == .restoreAll)
        c.handleMouseUp(at: .zero)
        workspace.frontmost = "com.a"                     // the Dock activated the app: expected here
        scheduler.fire()
        #expect(windows.performed.count == 1 && windows.performed[0].0 == .restoreAll)
    }
}
