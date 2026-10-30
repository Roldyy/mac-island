import Testing
@testable import DockFeature

@Suite struct DockClickDecisionTests {
    let all = DockClickOptions(minimize: true, hide: false, cycle: true)
    func w(min: Bool = false, full: Bool = false) -> DockWindow { DockWindow(isMinimized: min, isFullScreen: full) }
    func input(_ options: DockClickOptions? = nil, clicked: String? = "com.a", front: String? = "com.a",
               windows: [DockWindow], hidden: Bool = false) -> DockClickInput {
        DockClickInput(options: options ?? all, clickedBundleID: clicked, frontmostBundleID: front,
                       windows: windows, isHidden: hidden)
    }

    @Test func frontmostSingleWindowMinimizes() {
        #expect(DockClickDecision.decide(input(windows: [w()])) == .minimizeAll)
    }
    @Test func frontmostSeveralWindowsCycleToTheRearmostVisible() {
        #expect(DockClickDecision.decide(input(windows: [w(), w(), w()])) == .cycle(raiseWindowAt: 2))
        #expect(DockClickDecision.decide(input(windows: [w(), w(), w(min: true)])) == .cycle(raiseWindowAt: 1))
    }
    @Test func severalWindowsWithCycleOffMinimizeAll() {
        let o = DockClickOptions(minimize: true, hide: false, cycle: false)
        #expect(DockClickDecision.decide(input(o, windows: [w(), w()])) == .minimizeAll)
    }
    @Test func oneVisibleAmongMinimizedMinimizes() {
        #expect(DockClickDecision.decide(input(windows: [w(), w(min: true)])) == .minimizeAll)
    }
    @Test func onlyMinimizedWindowsRestoreEvenWhenNotFrontmost() {
        #expect(DockClickDecision.decide(input(front: "com.b", windows: [w(min: true), w(min: true)])) == .restoreAll)
        #expect(DockClickDecision.decide(input(windows: [w(min: true)])) == .restoreAll)
    }
    @Test func onlyMinimizedWithMinimizeOffDoesNothing() {
        let o = DockClickOptions(minimize: false, hide: true, cycle: true)
        #expect(DockClickDecision.decide(input(o, windows: [w(min: true)])) == .none)
    }
    @Test func notFrontmostWithVisibleWindowsIsLeftToTheSystem() {
        #expect(DockClickDecision.decide(input(front: "com.b", windows: [w()])) == .none)
    }
    @Test func zeroWindowsDoesNothing() {
        #expect(DockClickDecision.decide(input(windows: [])) == .none)
    }
    @Test func fullScreenWindowDoesNothing() {
        #expect(DockClickDecision.decide(input(windows: [w(full: true)])) == .none)
        #expect(DockClickDecision.decide(input(windows: [w(), w(full: true)])) == .none)
        #expect(DockClickDecision.decide(input(windows: [w(min: true), w(full: true)])) == .none)
    }
    @Test func theDockItselfAndMissingItemsDoNothing() {
        #expect(DockClickDecision.decide(input(clicked: "com.apple.dock", front: "com.apple.dock", windows: [w()])) == .none)
        #expect(DockClickDecision.decide(input(clicked: nil, windows: [w()])) == .none)
    }
    @Test func hiddenAppDoesNothing() {
        #expect(DockClickDecision.decide(input(windows: [w()], hidden: true)) == .none)
    }
    @Test func hideOnlyHidesTheFrontmostApp() {
        let o = DockClickOptions(minimize: false, hide: true, cycle: false)
        #expect(DockClickDecision.decide(input(o, windows: [w(), w()])) == .hide)
    }
    @Test func minimizeWinsOverHideWhenBothOn() {
        let o = DockClickOptions(minimize: true, hide: true, cycle: false)
        #expect(DockClickDecision.decide(input(o, windows: [w()])) == .minimizeAll)
    }
    @Test func cycleOnlyStillCycles() {
        let o = DockClickOptions(minimize: false, hide: false, cycle: true)
        #expect(DockClickDecision.decide(input(o, windows: [w(), w()])) == .cycle(raiseWindowAt: 1))
        #expect(DockClickDecision.decide(input(o, windows: [w()])) == .none)
    }
    @Test func allOptionsOffDoNothing() {
        let o = DockClickOptions(minimize: false, hide: false, cycle: false)
        #expect(DockClickDecision.decide(input(o, windows: [w(), w()])) == .none)
        #expect(DockClickDecision.decide(input(o, windows: [w(min: true)])) == .none)
    }
}
