/// The last N readings of a gauge, for the sparkline. Percent values, clamped to 0...100.
struct SampleHistory: Equatable, Sendable {
    static let defaultCapacity = 60

    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int = SampleHistory.defaultCapacity) {
        self.capacity = max(1, capacity)
        values.reserveCapacity(self.capacity)
    }

    mutating func append(_ value: Double) {
        if values.count == capacity { values.removeFirst() }
        values.append(min(100, max(0, value)))
    }
}
