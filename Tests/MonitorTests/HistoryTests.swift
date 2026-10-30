import Testing
@testable import MonitorFeature

@Suite struct HistoryTests {
    @Test func keepsOnlyTheLastSamples() {
        var h = SampleHistory(capacity: 3)
        for v in [1.0, 2, 3, 4, 5] { h.append(v) }
        #expect(h.values == [3, 4, 5])
    }

    @Test func defaultCapacityIsSixty() {
        var h = SampleHistory()
        for i in 0..<100 { h.append(Double(i)) }
        #expect(h.values.count == 60)
        #expect(h.values.first == 40)
        #expect(h.values.last == 99)
    }

    @Test func clampsToPercentRange() {
        var h = SampleHistory(capacity: 5)
        h.append(-4); h.append(130)
        #expect(h.values == [0, 100])
    }
}
