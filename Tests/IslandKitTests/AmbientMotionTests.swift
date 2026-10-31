import Foundation
import Testing
@testable import IslandKit

@Suite struct AmbientMotionTests {
    @Test func aTitleThatFitsNeverMoves() {
        for t in [0.0, 1.0, 7.3, 100] { #expect(AmbientMotion.marqueePhase(time: t, travel: 0) == 0) }
        #expect(AmbientMotion.marqueePhase(time: 5, travel: 0.5) == 0)
    }

    @Test func aLongTitleWaitsScrollsWaitsAndComesBack() {
        let travel: CGFloat = 44  // 2 s of travel at 22 pt/s
        let pause = AmbientMotion.marqueePause
        #expect(AmbientMotion.marqueePhase(time: 0, travel: travel) == 0)
        #expect(AmbientMotion.marqueePhase(time: pause - 0.01, travel: travel) == 0)
        let mid = AmbientMotion.marqueePhase(time: pause + 1, travel: travel)
        #expect(mid > 0.3 && mid < 0.7)
        #expect(AmbientMotion.marqueePhase(time: pause + 2 + 0.2, travel: travel) == 1)
        let back = AmbientMotion.marqueePhase(time: pause + 2 + pause + 1, travel: travel)
        #expect(back > 0.3 && back < 0.7)
        #expect(AmbientMotion.marqueePhase(time: 2 * (pause + 2) + 0.01, travel: travel) < 0.05)  // next cycle starts at 0
    }

    @Test func thePhaseStaysInRangeForAnyTime() {
        for t in stride(from: -50.0, through: 500, by: 0.37) {
            let p = AmbientMotion.marqueePhase(time: t, travel: 80)
            #expect(p >= 0 && p <= 1)
        }
        #expect(AmbientMotion.marqueePhase(time: .nan, travel: 80) == 0)
        #expect(AmbientMotion.marqueePhase(time: .infinity, travel: 80) == 0)
    }

    @Test func equalizerBarsDanceWithinRangeAndStandStillUnderReduceMotion() {
        for i in 0..<3 {
            let still = AmbientMotion.barLevel(i, time: 12.3, reduceMotion: true)
            #expect(still == AmbientMotion.barLevel(i, time: 99, reduceMotion: true))
            for t in stride(from: 0.0, through: 10, by: 0.13) {
                let level = AmbientMotion.barLevel(i, time: t, reduceMotion: false)
                #expect(level >= 0.3 && level <= 1)
            }
        }
        let a = AmbientMotion.barLevel(0, time: 1, reduceMotion: false)
        let b = AmbientMotion.barLevel(0, time: 1.2, reduceMotion: false)
        #expect(a != b)
        #expect(AmbientMotion.barLevel(7, time: 0, reduceMotion: true) == AmbientMotion.barLevel(2, time: 0, reduceMotion: true))
    }

    @Test func thePulseIsOneSwellThatStartsAndEndsAtRest() {
        #expect(AmbientMotion.pulseSwell(0) < 0.0001)
        #expect(AmbientMotion.pulseSwell(1) < 0.0001)
        #expect(AmbientMotion.pulseSwell(0.5) > 0.99)
        #expect(AmbientMotion.pulseSwell(-1) < 0.0001)
        #expect(AmbientMotion.pulseSwell(9) < 0.0001)
        #expect(AmbientMotion.pulseSwell(.nan) == 0)
    }
}
