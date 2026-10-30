import CoreGraphics
import Testing
@testable import DockFeature

@Suite struct ThumbnailLimitsTests {
    @Test func fitKeepsAspectAndNeverUpscales() {
        let max = CGSize(width: 200, height: 130)
        #expect(ThumbnailLimits.fit(CGSize(width: 1000, height: 500), into: max) == CGSize(width: 200, height: 100))
        #expect(ThumbnailLimits.fit(CGSize(width: 400, height: 800), into: max) == CGSize(width: 65, height: 130))
        #expect(ThumbnailLimits.fit(CGSize(width: 100, height: 50), into: max) == CGSize(width: 100, height: 50))
    }
    @Test func degenerateSizesYieldZero() {
        #expect(ThumbnailLimits.fit(.zero, into: CGSize(width: 10, height: 10)) == .zero)
        #expect(ThumbnailLimits.fit(CGSize(width: -1, height: 5), into: CGSize(width: 10, height: 10)) == .zero)
    }
    @Test func windowCountIsCapped() {
        #expect(ThumbnailLimits.cap(Array(0..<20)).count == ThumbnailLimits.maxWindows)
        #expect(ThumbnailLimits.cap([1, 2]).count == 2)
    }
    func allow(_ t: inout CaptureThrottle, _ key: Int32, _ now: Double) -> Bool { t.shouldCapture(key: key, now: now) }

    @Test func throttleBlocksRepeatsWithinTheInterval() {
        var t = CaptureThrottle(minInterval: 1)
        #expect(allow(&t, 1, 0))
        #expect(!allow(&t, 1, 0.5))
        #expect(allow(&t, 2, 0.5))
        #expect(allow(&t, 1, 1.0))
        t.reset()
        #expect(allow(&t, 2, 1.1))
    }
}
