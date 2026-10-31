import CoreGraphics
import Testing
@testable import IslandKit

@Suite struct IslandRevealCurveTests {
    typealias Curve = IslandRevealCurve
    let closed = CGSize(width: 232, height: 32)
    let open = CGSize(width: 660, height: 420)

    @Test func endpointsAreExact() {
        #expect(Curve.shapeSize(progress: 0, closed: closed, open: open) == closed)
        #expect(Curve.shapeSize(progress: 1, closed: closed, open: open) == open)
        #expect(Curve.cornerRadii(progress: 0) == (Curve.closedTopRadius, Curve.closedBottomRadius))
        #expect(Curve.cornerRadii(progress: 1) == (Curve.openTopRadius, Curve.openBottomRadius))
        #expect(Curve.contentOpacity(progress: 0) == 0)
        #expect(Curve.contentOpacity(progress: 1) == 1)
        #expect(Curve.closedOpacity(progress: 0) == 1)
        #expect(Curve.closedOpacity(progress: 1) == 0)
    }

    @Test func progressIsClampedAndNonFiniteIsClosed() {
        #expect(Curve.shapeSize(progress: 3, closed: closed, open: open) == open)
        #expect(Curve.shapeSize(progress: -1, closed: closed, open: open) == closed)
        #expect(Curve.clamp(.nan) == 0)
    }

    @Test func contentWaitsForTheShapeAndNeverOvershoots() {
        #expect(Curve.contentOpacity(progress: Curve.contentFadeStart) == 0)
        #expect(Curve.contentOpacity(progress: 0.2) == 0)
        var last = 0.0
        for i in 0...100 {
            let p = Double(i) / 100
            let o = Curve.contentOpacity(progress: p)
            #expect(o >= last && o <= 1)
            last = o
            #expect((0.97...1).contains(Curve.contentScale(progress: p)))
        }
    }

    @Test func backdropHandsOverToGlassOnlyWhenTranslucent() {
        #expect(Curve.backdropOpacity(progress: 1, translucent: false) == 1)
        #expect(Curve.backdropOpacity(progress: 1, translucent: true) == 0)
        #expect(Curve.backdropOpacity(progress: 0, translucent: true) == 1)
    }

    @Test func reduceMotionHasNoAnimationAndNoDuration() {
        #expect(Curve.animation(opening: true, reduceMotion: true) == nil)
        #expect(Curve.animation(opening: false, reduceMotion: true) == nil)
        #expect(Curve.animation(opening: true, reduceMotion: false) != nil)
        #expect(Curve.duration(opening: true, reduceMotion: true) == 0)
        #expect(Curve.duration(opening: true, reduceMotion: false) > Curve.duration(opening: false, reduceMotion: false))
        #expect(Curve.settleDelay > max(Curve.openDuration, Curve.closeDuration))
    }

    @Test func panelGrowsAtOnceAndShrinksLater() {
        let small = CGRect(x: 100, y: 868, width: 232, height: 32)
        let big = CGRect(x: 20, y: 480, width: 392, height: 420)
        let opening = IslandFramePlan.make(current: small, target: big, animated: true)
        #expect(opening.immediate == big && opening.settled == nil)
        let closing = IslandFramePlan.make(current: big, target: small, animated: true)
        #expect(closing.immediate == big && closing.settled == small)
        let instant = IslandFramePlan.make(current: big, target: small, animated: false)
        #expect(instant.immediate == small && instant.settled == nil)
        let same = IslandFramePlan.make(current: big, target: big, animated: true)
        #expect(same.immediate == big && same.settled == nil)
    }
}
