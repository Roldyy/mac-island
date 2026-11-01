import Foundation
import Testing
@testable import FinderFeature

/// Lane W7-A: once the ported engine owns the Finder key taps, the island tab must install none of its own (two taps on
/// one key would move every file twice) and must show the engine's state. Read-only: the model only reads the
/// Accessibility and Automation state here, it sends nothing to the Finder and touches no file.
@MainActor
@Suite(.serialized) final class EngineDeferralTests {
    private var made: [TempDefaults] = []

    private func model() -> FinderModel {
        let temp = TempDefaults()
        made.append(temp)
        return FinderModel(settings: FinderSettings(defaults: temp.defaults))
    }

    private func withHooks(status: (() -> FinderFeature.EngineStatus)?, sync: (() -> Void)? = nil,
                           cancel: (() -> Void)? = nil, _ body: () -> Void) {
        let saved = (FinderFeature.engineStatus, FinderFeature.engineSync, FinderFeature.engineCancelCut)
        FinderFeature.engineStatus = status
        FinderFeature.engineSync = sync
        FinderFeature.engineCancelCut = cancel
        body()
        (FinderFeature.engineStatus, FinderFeature.engineSync, FinderFeature.engineCancelCut) = saved
    }

    @Test func theTabShowsTheEnginesStateAndInstallsNoTapOfItsOwn() {
        withHooks(status: { .init(running: true, cutCount: 3) }) {
            let m = model()
            m.cutPasteEnabled = true
            m.start()
            m.refresh()
            // `tapRunning` can only be true here because the engine said so: this model started no tap.
            #expect(m.tapRunning)
            #expect(m.cutCount == 3)
            #expect(!m.needsConfirmation)
            #expect(m.cutLine == "Coupé : 3")
            m.stop()
        }
    }

    @Test func theTwoSwitchesAreForwardedToTheEngine() {
        var syncs = 0
        withHooks(status: { .init(running: false, cutCount: 0) }, sync: { syncs += 1 }) {
            let m = model()
            m.cutPasteEnabled = true
            m.pasteImageAsFile = false
            #expect(syncs == 2, "each switch asks the engine to re-read the preferences")
        }
    }

    @Test func cancellingTheCutGoesToTheEngineNotToTheOldController() {
        var cancels = 0
        withHooks(status: { .init(running: true, cutCount: 2) }, cancel: { cancels += 1 }) {
            let m = model()
            m.cancelCut()
            #expect(cancels == 1)
        }
    }

    @Test func withoutAnEngineTheTabKeepsItsOwnBehaviour() {
        var syncs = 0
        withHooks(status: nil, sync: { syncs += 1 }) {
            let m = model()
            m.cutPasteEnabled = false  // not started: no tap, nothing running, the old path
            #expect(!m.tapRunning)
            #expect(m.cutCount == 0)
        }
        #expect(syncs == 1, "the forward hook is independent of the status hook")
    }
}
