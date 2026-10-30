import Foundation

/// Delay before the next reconnect attempt: doubles from `initial` up to `maximum`.
struct ReconnectBackoff: Equatable, Sendable {
    var initial: TimeInterval = 0.5
    var maximum: TimeInterval = 30
    private(set) var attempts = 0

    init(initial: TimeInterval = 0.5, maximum: TimeInterval = 30) {
        self.initial = initial
        self.maximum = maximum
    }

    mutating func next() -> TimeInterval {
        let delay = min(maximum, initial * pow(2, Double(attempts)))
        attempts = min(attempts + 1, 30)
        return delay
    }

    mutating func reset() { attempts = 0 }
}
