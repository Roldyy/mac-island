import Foundation

/// The island keeps the Mac awake for two minutes after it is opened or used (`notchKeepAwakeActivity`), with no
/// session involved. This is the one thing our old controller did that the ported manager does not: a plain power
/// assertion with a deadline. The clock and IOKit are injected.
@MainActor
final class IslandActivityHold {
    /// How long a note of island activity keeps the Mac awake.
    nonisolated static let holdDuration: TimeInterval = 120

    private let assertion: AssertionSet
    private let settings: KeepAwakeSettings
    private let clock: () -> Date
    private let runsLoop: Bool
    private let tickInterval: Duration
    private var until: Date?
    private var loop: Task<Void, Never>?

    init(power: PowerAssertionProviding = IOKitPowerAssertions(), settings: KeepAwakeSettings = KeepAwakeSettings(),
         clock: @escaping () -> Date = Date.init, runsLoop: Bool = true, tickInterval: Duration = .seconds(1)) {
        assertion = AssertionSet(power: power)
        self.settings = settings
        self.clock = clock
        self.runsLoop = runsLoop
        self.tickInterval = tickInterval
    }

    // No deinit: `assertion` releases in its own deinit, and the loop holds self weakly.

    var isHolding: Bool { until != nil }

    /// The shell calls this when the island opens or is used. Honours `notchKeepAwakeActivity`.
    func note() {
        guard settings.activityKeepsAwake else { return }
        guard assertion.acquire([.idleSystemSleep], reason: "Mac Island in use") else { return }
        until = clock().addingTimeInterval(Self.holdDuration)
        ensureLoop()
    }

    func tick() {
        if let until, clock() >= until { release() }
    }

    func release() {
        assertion.releaseAll()
        until = nil
        loop?.cancel()
        loop = nil
    }

    private func ensureLoop() {
        guard runsLoop, loop == nil else { return }
        loop = Task { [weak self, tickInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard let self else { return }
                self.tick()
            }
        }
    }
}
