import Testing
@testable import DisplayFeature

@Suite @MainActor struct BrightnessModelTests {
    private func make(_ level: Float?) -> (BrightnessModel, FakeBrightnessBackend) {
        let backend = FakeBrightnessBackend(level: level)
        return (BrightnessModel(backend: backend, debounce: 0.05, sleep: { _ in }), backend)
    }

    @Test func unavailableWhenReadFailsAndNothingIsWritten() async {
        let (model, backend) = make(nil)
        model.refresh()
        #expect(model.isAvailable == false)
        model.setLevel(0.5)
        await model.pendingWrite?.value
        model.nudge(.up)
        await model.pendingWrite?.value
        #expect(backend.writes.isEmpty)
    }

    @Test func refreshReadsTheCurrentLevel() {
        let (model, backend) = make(0.4)
        model.refresh()
        #expect(model.isAvailable)
        #expect(abs(model.level - 0.4) < 0.0001)
        backend.level = 0.7
        model.refresh()
        #expect(abs(model.level - 0.7) < 0.0001)
    }

    @Test func levelIsClampedToUnitRange() async {
        let (model, backend) = make(0.5)
        model.refresh()
        model.setLevel(1.7)
        await model.pendingWrite?.value
        #expect(model.level == 1)
        #expect(backend.writes.last == 1)
        model.setLevel(-0.3)
        await model.pendingWrite?.value
        #expect(model.level == 0)
        #expect(backend.writes.last == 0)
    }

    @Test func nonFiniteInputIsIgnored() async {
        let (model, backend) = make(0.5)
        model.refresh()
        model.setLevel(.nan)
        model.setLevel(.infinity)
        await model.pendingWrite?.value
        #expect(model.level == 0.5)
        #expect(backend.writes.isEmpty)
    }

    @Test func stepsMoveOneSixteenthAndStopAtTheEnds() async {
        let (model, backend) = make(0.5)
        model.refresh()
        model.nudge(.up)
        await model.pendingWrite?.value
        #expect(abs(model.level - 0.5625) < 0.0001)
        model.nudge(.down)
        model.nudge(.down)
        await model.pendingWrite?.value
        #expect(abs(model.level - 0.4375) < 0.0001)
        #expect(backend.writes.count == 2)  // one for the first step, one for the two coalesced downs
    }

    @Test func stepsClampAtBounds() async {
        let (top, _) = make(0.99)
        top.refresh()
        top.nudge(.up)
        await top.pendingWrite?.value
        #expect(top.level == 1)
        let (bottom, _) = make(0.01)
        bottom.refresh()
        bottom.nudge(.down)
        await bottom.pendingWrite?.value
        #expect(bottom.level == 0)
    }

    @Test func rapidChangesAreDebouncedToTheLastValue() async {
        let (model, backend) = make(0.5)
        model.refresh()
        model.setLevel(0.1)
        model.setLevel(0.2)
        model.setLevel(0.3)
        await model.pendingWrite?.value
        #expect(backend.writes == [0.3])
    }

    @Test func restoreWritesTheStartingLevelImmediately() async {
        let (model, backend) = make(0.4)
        model.refresh()
        model.setLevel(0.9)
        await model.pendingWrite?.value
        model.restoreInitial()
        #expect(abs(model.level - 0.4) < 0.0001)
        #expect(backend.writes.last == 0.4)
    }

    @Test func restoreCancelsAPendingWrite() async {
        let (model, backend) = make(0.4)
        model.refresh()
        model.setLevel(0.9)
        model.restoreInitial()
        await model.pendingWrite?.value
        #expect(backend.writes == [0.4])
    }

    @Test func failedWriteMarksTheFeatureUnavailableWithoutCrashing() async {
        let (model, backend) = make(0.5)
        model.refresh()
        backend.writeSucceeds = false
        model.setLevel(0.8)
        await model.pendingWrite?.value
        #expect(model.isAvailable == false)
    }
}
