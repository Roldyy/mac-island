import CoreGraphics
import Foundation
import Testing
@testable import IslandKit

/// The closed strip's animations all hang on one decision: is the strip on screen right now? Pure, no view, no clock.
@Suite struct AmbientClockPolicyTests {
    private typealias Inputs = AmbientClockInputs

    @Test func runsWhenTheClosedStripIsOnScreen() {
        #expect(AmbientClockPolicy.stripIsVisible(Inputs()))
        #expect(AmbientClockPolicy.animationsRun(Inputs(), reduceMotion: false))
    }

    @Test func pausesWhileTheIslandIsOpen() {
        let open = Inputs(islandOpen: true)
        #expect(!AmbientClockPolicy.stripIsVisible(open))
        #expect(!AmbientClockPolicy.animationsRun(open, reduceMotion: false))
    }

    @Test func pausesWhenThePanelIsOccluded() {
        #expect(!AmbientClockPolicy.stripIsVisible(Inputs(panelOccluded: true)))
    }

    @Test func pausesWhileTheScreenSleeps() {
        #expect(!AmbientClockPolicy.stripIsVisible(Inputs(screenAsleep: true)))
    }

    @Test func pausesWhenTheSessionIsLockedOrSwitchedAway() {
        #expect(!AmbientClockPolicy.stripIsVisible(Inputs(sessionActive: false)))
    }

    @Test func resumesWhenEveryReasonToPauseIsGone() {
        var inputs = Inputs(islandOpen: true, panelOccluded: true, screenAsleep: true, sessionActive: false)
        inputs.islandOpen = false
        inputs.panelOccluded = false
        inputs.screenAsleep = false
        #expect(!AmbientClockPolicy.stripIsVisible(inputs), "the session is still locked")
        inputs.sessionActive = true
        #expect(AmbientClockPolicy.stripIsVisible(inputs))
    }

    @Test func reduceMotionStopsTheMotionButNotTheTextClock() {
        let inputs = Inputs()
        #expect(!AmbientClockPolicy.animationsRun(inputs, reduceMotion: true))
        #expect(AmbientClockPolicy.textClockRuns(inputs), "elapsed time is information, not motion")
        #expect(!AmbientClockPolicy.textClockRuns(Inputs(screenAsleep: true)))
    }

    @Test func frameRatesAreCapped() {
        #expect(AmbientClockPolicy.equalizerFPS <= 12)
        #expect(AmbientClockPolicy.ringFPS <= 15)
        #expect(AmbientClockPolicy.marqueeFPS <= 20)
        #expect(AmbientClockPolicy.interval(forFPS: 12) == 1.0 / 12.0)
        #expect(AmbientClockPolicy.interval(forFPS: 0) == 1, "a bad rate falls back to one tick a second")
    }

    @Test func marqueeRunsOnlyWhenTheTextOverflowsItsSlot() {
        #expect(AmbientClockPolicy.marqueeRuns(textWidth: 90, slot: 60, reduceMotion: false))
        #expect(!AmbientClockPolicy.marqueeRuns(textWidth: 60, slot: 60, reduceMotion: false))
        #expect(!AmbientClockPolicy.marqueeRuns(textWidth: 40, slot: 60, reduceMotion: false))
        #expect(!AmbientClockPolicy.marqueeRuns(textWidth: 90, slot: 60, reduceMotion: true))
    }

    @Test func secondsTickEverySecondAndMinutesAtTheMinuteBoundary() {
        #expect(AmbientClockPolicy.textTick(showsSeconds: true, after: Date(timeIntervalSince1970: 100.4)) == 1)
        // 100 s after the epoch is 1:40: the next boundary is 20 s away.
        let wait = AmbientClockPolicy.textTick(showsSeconds: false, after: Date(timeIntervalSince1970: 100))
        #expect(abs(wait - 20) < 0.001)
        let onBoundary = AmbientClockPolicy.textTick(showsSeconds: false, after: Date(timeIntervalSince1970: 120))
        #expect(abs(onBoundary - 60) < 0.001)
    }
}
