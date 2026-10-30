import Testing
@testable import DockFeature

@Suite struct PreviewStateMachineTests {
    func machine(delay: Double = 0.4, grace: Double = 0.3) -> PreviewStateMachine {
        PreviewStateMachine(delay: delay, grace: grace)
    }

    func step(_ m: inout PreviewStateMachine, _ icon: String?, _ panel: Bool, _ t: Double) -> PreviewStateMachine.Command {
        m.update(hoveredIcon: icon, overPanel: panel, now: t)
    }
    func cancel(_ m: inout PreviewStateMachine) -> PreviewStateMachine.Command { m.cancel() }

    @Test func restingOnTheIconShowsOnlyAfterTheDelay() {
        var m = machine()
        #expect(step(&m, "a", false, 0) == .none)
        #expect(step(&m, "a", false, 0.39) == .none)
        #expect(step(&m, "a", false, 0.4) == .show("a"))
        #expect(m.phase == .showing(id: "a"))
    }
    @Test func zeroDelayShowsAtOnce() {
        var m = machine(delay: 0)
        #expect(step(&m, "a", false, 5) == .show("a"))
    }
    @Test func leavingBeforeTheDelayCancels() {
        var m = machine()
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        #expect(step(&m, nil, false, 0.2) == .none)
        #expect(m.phase == .idle)
        #expect(step(&m, nil, false, 9) == .none)
    }
    @Test func movingToAnotherIconRestartsTheDelay() {
        var m = machine()
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        #expect(step(&m, "b", false, 0.3) == .none)
        #expect(step(&m, "b", false, 0.6) == .none)
        #expect(step(&m, "b", false, 0.8) == .show("b"))
    }
    @Test func hidesOnlyAfterTheGracePeriod() {
        var m = machine()
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0.4)
        #expect(step(&m, nil, false, 1.0) == .none)
        #expect(step(&m, nil, false, 1.29) == .none)
        #expect(step(&m, nil, false, 1.3) == .hide)
        #expect(m.phase == .idle)
    }
    @Test func enteringThePanelDuringGraceKeepsItOpen() {
        var m = machine()
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0.4)
        _ = m.update(hoveredIcon: nil, overPanel: false, now: 1.0)
        #expect(step(&m, nil, true, 1.2) == .none)
        #expect(m.phase == .showing(id: "a"))
        #expect(step(&m, nil, true, 50) == .none)
        #expect(step(&m, nil, false, 51) == .none)
        #expect(step(&m, nil, false, 51.5) == .hide)
    }
    @Test func comingBackToTheSameIconDuringGraceKeepsItOpen() {
        var m = machine()
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0.4)
        _ = m.update(hoveredIcon: nil, overPanel: false, now: 1.0)
        #expect(step(&m, "a", false, 1.2) == .none)
        #expect(m.phase == .showing(id: "a"))
    }
    @Test func anotherIconSwitchesTheOpenPreviewImmediately() {
        var m = machine()
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0.4)
        #expect(step(&m, "b", false, 0.5) == .show("b"))
        _ = m.update(hoveredIcon: nil, overPanel: false, now: 0.6)
        #expect(step(&m, "c", false, 0.7) == .show("c"))
    }
    @Test func cancelHidesAnOpenPreviewAndIsSilentOtherwise() {
        var m = machine()
        #expect(cancel(&m) == .none)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        #expect(cancel(&m) == .none)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 1)
        #expect(cancel(&m) == .none)
        #expect(m.phase == .idle)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 2)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 2.4)
        #expect(cancel(&m) == .hide)
        #expect(m.phase == .idle)
    }
    @Test func isIdleReflectsThePhase() {
        var m = machine()
        #expect(m.isIdle)
        _ = m.update(hoveredIcon: "a", overPanel: false, now: 0)
        #expect(!m.isIdle)
    }
}
