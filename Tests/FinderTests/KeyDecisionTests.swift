import Testing
@testable import FinderFeature

@Suite struct KeyDecisionTests {
    func ctx(finder: Bool = true, editing: Bool = false, cut: Bool = false, files: Bool = false,
             image: Bool = false, cutOn: Bool = true, imgOn: Bool = true) -> FinderKeyContext {
        FinderKeyContext(finderFrontmost: finder, textEditing: editing, hasPendingCut: cut,
                         pasteboardHasFileURLs: files, pasteboardHasImage: image,
                         cutPasteEnabled: cutOn, imagePasteEnabled: imgOn)
    }
    func cmd(_ key: Int, shift: Bool = false, option: Bool = false, control: Bool = false,
             command: Bool = true, rep: Bool = false) -> KeyChord {
        KeyChord(keyCode: key, command: command, shift: shift, option: option, control: control, isRepeat: rep)
    }

    @Test func cmdXSwallowsInFinder() {
        #expect(KeyDecision.decide(cmd(KeyCode.x), ctx()) == .swallowCut)
    }
    @Test func cmdXRepeatSwallowedWithoutAction() {
        #expect(KeyDecision.decide(cmd(KeyCode.x, rep: true), ctx()) == .swallowRepeat)
    }
    @Test func cmdXPassesWhenNotFinderOrEditingOrDisabled() {
        #expect(KeyDecision.decide(cmd(KeyCode.x), ctx(finder: false)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.x), ctx(editing: true)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.x), ctx(cutOn: false)) == .pass)
    }
    @Test func wrongModifiersPass() {
        #expect(KeyDecision.decide(cmd(KeyCode.x, command: false), ctx()) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.x, shift: true), ctx()) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.x, option: true), ctx()) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.x, control: true), ctx()) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.v, shift: true), ctx(cut: true)) == .pass)
        // Cmd+Option+V is Finder's own "Move Item Here": never touched.
        #expect(KeyDecision.decide(cmd(KeyCode.v, option: true), ctx(cut: true)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.v, command: false), ctx(cut: true)) == .pass)
    }
    @Test func cmdVMovesWhenCutPending() {
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(cut: true)) == .swallowPasteMove)
        #expect(KeyDecision.decide(cmd(KeyCode.v, rep: true), ctx(cut: true)) == .swallowRepeat)
    }
    @Test func cmdVNothingCutPasses() {
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx()) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(cut: true, cutOn: false)) == .pass)
    }
    @Test func cmdVImageOnly() {
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(image: true)) == .swallowPasteImage)
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(files: true, image: true)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(image: true, imgOn: false)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(editing: true, image: true)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(finder: false, image: true)) == .pass)
    }
    @Test func cutWinsOverImage() {
        #expect(KeyDecision.decide(cmd(KeyCode.v), ctx(cut: true, image: true)) == .swallowPasteMove)
    }
    @Test func escCancelsOnlyPendingCutAndNeverSwallows() {
        #expect(KeyDecision.decide(cmd(KeyCode.esc, command: false), ctx(cut: true)) == .passAndCancelCut)
        #expect(KeyDecision.decide(cmd(KeyCode.esc, command: false), ctx(cut: false)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.esc, command: false), ctx(editing: true, cut: true)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.esc, command: true), ctx(cut: true)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.esc, command: false), ctx(finder: false, cut: true)) == .pass)
    }
    @Test func cmdCCancelsPendingCutButPasses() {
        #expect(KeyDecision.decide(cmd(KeyCode.c), ctx(cut: true)) == .passAndCancelCut)
        #expect(KeyDecision.decide(cmd(KeyCode.c), ctx(cut: false)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.c), ctx(editing: true, cut: true)) == .pass)
        #expect(KeyDecision.decide(cmd(KeyCode.c, shift: true), ctx(cut: true)) == .pass)
    }
    @Test func otherKeysPass() {
        #expect(KeyDecision.decide(cmd(0), ctx(cut: true)) == .pass)
        #expect(!KeyDecision.isCandidate(cmd(0)))
        #expect(KeyDecision.isCandidate(cmd(KeyCode.v)))
    }
    @Test func swallowFlags() {
        #expect(KeyDecision.swallowCut.swallows)
        #expect(KeyDecision.swallowPasteMove.swallows)
        #expect(KeyDecision.swallowPasteImage.swallows)
        #expect(KeyDecision.swallowRepeat.swallows)
        #expect(!KeyDecision.pass.swallows)
        #expect(!KeyDecision.passAndCancelCut.swallows)
    }
}
