import CoreGraphics
import Testing
@testable import DockFeature

@MainActor final class FakeResolver: DockItemResolving {
    var app: DockApp?
    var calls = 0
    func app(at point: CGPoint) -> DockApp? { calls += 1; return app }
}

@MainActor final class FakeWindows: AppWindowAccessing {
    var windows: [DockWindow] = []
    var performed: [(DockClickAction, Int32)] = []
    var raised: [(Int32, Int)] = []
    func windows(pid: Int32) -> [DockWindow] { windows }
    func perform(_ action: DockClickAction, pid: Int32) { performed.append((action, pid)) }
    func raise(pid: Int32, windowAt index: Int) { raised.append((pid, index)) }
}

@MainActor final class FakeWorkspace: WorkspaceQuerying {
    var frontmost: String?
    var hidden = false
    var frontmostBundleID: String? { frontmost }
    func isHidden(pid: Int32) -> Bool { hidden }
}

@MainActor @Suite struct DockClickControllerTests {
    let resolver = FakeResolver()
    let windows = FakeWindows()
    let workspace = FakeWorkspace()

    func make(_ o: DockClickOptions = DockClickOptions(minimize: true, hide: false, cycle: true)) -> DockClickController {
        return DockClickController(options: { o }, resolver: resolver, windows: windows, workspace: workspace)
    }
    let app = DockApp(bundleID: "com.a", pid: 42, iconFrame: .zero)

    @Test func frontmostClickMinimizes() {
        resolver.app = app; workspace.frontmost = "com.a"; windows.windows = [DockWindow()]
        let a = make().handleMouseDown(at: .zero)
        #expect(a == .minimizeAll)
        #expect(windows.performed.count == 1 && windows.performed[0].1 == 42)
    }
    @Test func clickOffTheDockDoesNotTouchWindows() {
        resolver.app = nil
        #expect(make().handleMouseDown(at: .zero) == .none)
        #expect(windows.performed.isEmpty)
    }
    @Test func allOptionsOffSkipsTheAccessibilityLookup() {
        resolver.app = app
        _ = make(DockClickOptions(minimize: false, hide: false, cycle: false)).handleMouseDown(at: .zero)
        #expect(resolver.calls == 0)
    }
    @Test func nothingDecisionPerformsNothing() {
        resolver.app = app; workspace.frontmost = "com.b"; windows.windows = [DockWindow()]
        #expect(make().handleMouseDown(at: .zero) == .none)
        #expect(windows.performed.isEmpty)
    }
    @Test func hiddenAppIsNotTouched() {
        resolver.app = app; workspace.frontmost = "com.a"; workspace.hidden = true; windows.windows = [DockWindow()]
        #expect(make().handleMouseDown(at: .zero) == .none)
    }
}
