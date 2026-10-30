import Testing
@testable import AudioFeature

@Suite struct VolumeCurveTests {
    @Test func endpoints() {
        #expect(VolumeCurve.gain(forPosition: 0) == 0)
        #expect(VolumeCurve.gain(forPosition: 1) == 1)
    }

    @Test func monotonic() {
        var last: Float = -1
        for i in 0...100 {
            let g = VolumeCurve.gain(forPosition: Double(i) / 100)
            #expect(g > last || i == 0 && g == 0)
            last = g
        }
    }

    @Test func roundTrip() {
        for i in 0...20 {
            let p = Double(i) / 20
            let back = VolumeCurve.position(forGain: VolumeCurve.gain(forPosition: p))
            #expect(abs(back - p) < 1e-5)
        }
    }

    @Test func clampsAndRejectsNaN() {
        #expect(VolumeCurve.gain(forPosition: -3) == 0)
        #expect(VolumeCurve.gain(forPosition: 7) == 1)
        #expect(VolumeCurve.gain(forPosition: .nan) == 0)
        #expect(VolumeCurve.position(forGain: 9) == 1)
        #expect(VolumeCurve.position(forGain: -1) == 0)
    }

    @Test func midPositionIsQuieterThanLinear() {
        #expect(VolumeCurve.gain(forPosition: 0.5) == 0.25)
    }
}
