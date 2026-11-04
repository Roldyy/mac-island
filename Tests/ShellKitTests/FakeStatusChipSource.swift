import Foundation
@testable import ShellKit

/// A source driven by hand: counts the calls the feed makes and publishes what the test pushes.
@MainActor
final class FakeStatusChipSource: StatusChipSource {
    let kind: StatusChipKind
    private(set) var reading: StatusChipReading?
    var onChange: (@MainActor () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false
    /// Published by `start()`, like a source that knows its value at once.
    var firstReading: StatusChipReading?

    init(_ kind: StatusChipKind, first: StatusChipReading? = nil) {
        self.kind = kind
        firstReading = first
    }

    func start() {
        startCount += 1
        isRunning = true
        if let firstReading { push(firstReading) }
    }

    func stop() {
        stopCount += 1
        isRunning = false
        reading = nil
    }

    /// The source samples something new.
    func push(_ new: StatusChipReading?) {
        reading = new
        onChange?()
    }
}

extension StatusChipReading {
    /// A short reading of `kind` for tests.
    static func sample(_ kind: StatusChipKind, _ text: String = "ok", level: Level = .normal) -> StatusChipReading {
        StatusChipReading(kind: kind, primary: text, level: level)
    }
}
