import Foundation
import Testing
@testable import FinderFeature

@Suite struct FinderKeyStateTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func chord(_ code: Int, command: Bool = true, shift: Bool = false, rep: Bool = false) -> KeyChord {
        KeyChord(keyCode: code, command: command, shift: shift, option: false, control: false, isRepeat: rep)
    }
    func snap(frontmost: Bool = true, cut: Bool = false, cutOn: Bool = true, imageOn: Bool = false,
              inFlight: Int = 0, pbCount: Int? = 7) -> FinderKeySnapshot {
        var s = FinderKeySnapshot()
        s.finderFrontmost = frontmost
        s.cutPasteEnabled = cutOn
        s.imagePasteEnabled = imageOn
        s.inFlightCuts = inFlight
        if cut { s.cutExpiresAt = t0.addingTimeInterval(PendingCut.lifetime); s.cutPasteboardChangeCount = pbCount }
        return s
    }

    @Test func noFullDecisionOutsideFinderOrForOtherKeys() {
        #expect(!snap(frontmost: false).needsFullDecision(chord(KeyCode.x), now: t0, pasteboardChangeCount: 7))
        #expect(!snap().needsFullDecision(chord(0), now: t0, pasteboardChangeCount: 7))
        #expect(!snap().needsFullDecision(chord(KeyCode.x, command: false), now: t0, pasteboardChangeCount: 7))
        #expect(!snap().needsFullDecision(chord(KeyCode.x, shift: true), now: t0, pasteboardChangeCount: 7))
    }
    @Test func cmdXNeedsTheCutSetting() {
        #expect(snap().needsFullDecision(chord(KeyCode.x), now: t0, pasteboardChangeCount: 7))
        #expect(!snap(cutOn: false).needsFullDecision(chord(KeyCode.x), now: t0, pasteboardChangeCount: 7))
    }
    @Test func cmdVNeedsAPendingCutOrImagePaste() {
        #expect(!snap().needsFullDecision(chord(KeyCode.v), now: t0, pasteboardChangeCount: 7))
        #expect(snap(cut: true).needsFullDecision(chord(KeyCode.v), now: t0, pasteboardChangeCount: 7))
        #expect(snap(imageOn: true).needsFullDecision(chord(KeyCode.v), now: t0, pasteboardChangeCount: 7))
        #expect(snap(inFlight: 1).needsFullDecision(chord(KeyCode.v), now: t0, pasteboardChangeCount: 7))
    }
    @Test func copyAndEscapeOnlyMatterWithAPendingCut() {
        #expect(!snap().needsFullDecision(chord(KeyCode.c), now: t0, pasteboardChangeCount: 7))
        #expect(snap(cut: true).needsFullDecision(chord(KeyCode.c), now: t0, pasteboardChangeCount: 7))
        #expect(!snap(cut: true).needsFullDecision(chord(KeyCode.esc, command: false, shift: true), now: t0, pasteboardChangeCount: 7))
        #expect(snap(cut: true).needsFullDecision(chord(KeyCode.esc, command: false), now: t0, pasteboardChangeCount: 7))
    }
    @Test func pendingCutExpiresAndDiesWithAPasteboardChange() {
        let s = snap(cut: true)
        #expect(s.hasPendingCut(now: t0, pasteboardChangeCount: 7))
        #expect(s.hasPendingCut(now: t0.addingTimeInterval(PendingCut.lifetime), pasteboardChangeCount: 7))
        #expect(!s.hasPendingCut(now: t0.addingTimeInterval(PendingCut.lifetime + 1), pasteboardChangeCount: 7))
        #expect(!s.hasPendingCut(now: t0, pasteboardChangeCount: 8))
        #expect(snap().hasPendingCut(now: t0, pasteboardChangeCount: 7) == false)
        #expect(snap(inFlight: 1).hasPendingCut(now: t0, pasteboardChangeCount: 99))
    }
    @Test func applyTracksInFlightCutAndCancel() {
        var s = snap(cut: true)
        s.apply(.swallowCut)
        #expect(s.inFlightCuts == 1)
        s.apply(.passAndCancelCut)
        #expect(s.cutExpiresAt == nil && s.cutPasteboardChangeCount == nil)
        s.apply(.swallowPasteMove); s.apply(.pass); s.apply(.swallowRepeat)
        #expect(s.inFlightCuts == 1)
    }
    @Test func stateIsSafeFromManyThreads() async {
        let state = FinderKeyState()
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<8 {
                g.addTask { for _ in 0..<500 { state.update { $0.apply(.swallowCut) }; _ = state.read() } }
            }
        }
        #expect(state.read().inFlightCuts == 4000)
    }
}

@Suite struct FinderFocusTests {
    @Test func finderOwnsTheKeyboardOnlyWhenFrontmostAndFocused() {
        #expect(FinderFocus.ownsKeyboard(finderFrontmost: true, focusedAppPID: 100, finderPID: 100))
        #expect(!FinderFocus.ownsKeyboard(finderFrontmost: false, focusedAppPID: 100, finderPID: 100))
        #expect(!FinderFocus.ownsKeyboard(finderFrontmost: true, focusedAppPID: 200, finderPID: 100))
        #expect(!FinderFocus.ownsKeyboard(finderFrontmost: true, focusedAppPID: nil, finderPID: 100))
        #expect(!FinderFocus.ownsKeyboard(finderFrontmost: true, focusedAppPID: 100, finderPID: nil))
    }
}

/// The tap thread's decision: no main actor anywhere.
@Suite struct FinderKeyEvaluatorTests {
    let t0 = Date(timeIntervalSince1970: 5_000)
    func chord(_ code: Int, command: Bool = true) -> KeyChord {
        KeyChord(keyCode: code, command: command, shift: false, option: false, control: false, isRepeat: false)
    }
    func make(env: FakeEnvironment, pb: FakePasteboard = FakePasteboard()) -> (FinderKeyEvaluator, FinderKeyState) {
        let state = FinderKeyState()
        state.update { $0.finderFrontmost = true; $0.cutPasteEnabled = true; $0.imagePasteEnabled = true }
        return (FinderKeyEvaluator(environment: env, pasteboard: pb, state: state, clock: { Date(timeIntervalSince1970: 5_000) }), state)
    }

    @Test func decidesOffTheMainThreadAndAppliesTheStateChange() async {
        let (ev, state) = make(env: FakeEnvironment())
        let x = chord(KeyCode.x)
        let d = await Task.detached { ev.decideApplying(x) }.value
        #expect(d == .swallowCut)
        #expect(state.read().inFlightCuts == 1)
        // Cmd+V typed before Finder answered is already ours.
        let v = chord(KeyCode.v)
        let d2 = await Task.detached { ev.decideApplying(v) }.value
        #expect(d2 == .swallowPasteMove)
    }
    @Test func unrelatedKeysCostNoAccessibilityQuery() {
        let env = FakeEnvironment()
        let (ev, state) = make(env: env)
        #expect(ev.decide(chord(0)) == .pass)
        #expect(ev.decide(chord(KeyCode.c)) == .pass)
        #expect(ev.decide(chord(KeyCode.esc, command: false)) == .pass)
        state.update { $0.finderFrontmost = false }
        #expect(ev.decide(chord(KeyCode.x)) == .pass)
        #expect(env.editingQueries == 0)
    }
    @Test func focusInAnotherAppPasses() {
        let env = FakeEnvironment(); env.focusedPID = 200
        let (ev, _) = make(env: env)
        #expect(ev.decide(chord(KeyCode.x)) == .pass)
        #expect(env.editingQueries == 0)
    }
    @Test func textEditingPasses() {
        let env = FakeEnvironment(); env.editing = true
        let (ev, _) = make(env: env)
        #expect(ev.decide(chord(KeyCode.x)) == .pass)
    }
    @Test func pasteboardChangeEndsThePendingCutOnTheTapThread() {
        let pb = FakePasteboard(); pb.changeCount = 3
        let (ev, state) = make(env: FakeEnvironment(), pb: pb)
        state.update { $0.cutExpiresAt = Date(timeIntervalSince1970: 5_100); $0.cutPasteboardChangeCount = 3 }
        #expect(ev.decide(chord(KeyCode.v)) == .swallowPasteMove)
        pb.changeCount = 4
        #expect(ev.decide(chord(KeyCode.v)) == .pass)
    }
}
