import Foundation
import Observation

enum JiggleStatus: Equatable {
    case off
    case needsAccessibility
    case waiting(intervalMinutes: Int)
}

/// Power assertions, the optional session duration and the mouse jiggle. IOKit, the clock, idle time,
/// Accessibility and CGEvent are all injected.
@MainActor @Observable
final class KeepAwakeController {
    /// How long a note of island activity keeps the Mac awake.
    nonisolated static let activityHold: TimeInterval = 120

    private(set) var plan: SessionPlan?
    private(set) var jiggleStatus: JiggleStatus = .off
    var isActive: Bool { plan != nil }

    @ObservationIgnored private let session: AssertionSet
    @ObservationIgnored private let activity: AssertionSet
    @ObservationIgnored private let jiggler: MouseJiggling
    @ObservationIgnored private let settings: KeepAwakeSettings
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let idleSeconds: () -> TimeInterval
    @ObservationIgnored private let accessibilityTrusted: () -> Bool
    @ObservationIgnored private let runsLoop: Bool
    @ObservationIgnored private let tickInterval: Duration
    @ObservationIgnored private var scheduler: JiggleScheduler
    @ObservationIgnored private var activityUntil: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(power: PowerAssertionProviding = IOKitPowerAssertions(),
         jiggler: MouseJiggling = CGEventMouseJiggler(),
         settings: KeepAwakeSettings = KeepAwakeSettings(),
         clock: @escaping () -> Date = Date.init,
         idleSeconds: @escaping () -> TimeInterval = SystemProbes.idleSeconds,
         accessibilityTrusted: @escaping () -> Bool = SystemProbes.accessibilityTrusted,
         runsLoop: Bool = true, tickInterval: Duration = .seconds(1)) {
        session = AssertionSet(power: power)
        activity = AssertionSet(power: power)
        self.jiggler = jiggler
        self.settings = settings
        self.clock = clock
        self.idleSeconds = idleSeconds
        self.accessibilityTrusted = accessibilityTrusted
        self.runsLoop = runsLoop
        self.tickInterval = tickInterval
        scheduler = JiggleScheduler(intervalMinutes: settings.mouseJiggleIntervalMinutes)
    }

    // No deinit: `session` and `activity` release their assertions in their own deinit, and the loop holds self weakly.

    /// Seconds; nil = no limit. A second call while active is ignored.
    func start(duration: TimeInterval?) {
        guard plan == nil else { return }
        var kinds: [AssertionKind] = [.idleSystemSleep]
        if settings.preventDisplaySleep { kinds.append(.idleDisplaySleep) }
        guard session.acquire(kinds, reason: "Mac Island keep awake") else { return }
        plan = SessionPlan(start: clock(), duration: duration)
        scheduler = JiggleScheduler(intervalMinutes: settings.mouseJiggleIntervalMinutes)
        refreshJiggleStatus()
        ensureLoop()
    }

    func stop() {
        session.releaseAll()
        plan = nil
        jiggleStatus = .off
        scheduler.reset()
        stopLoopIfIdle()
    }

    /// The shell calls this when the island opens or is used. Holds an assertion for `activityHold`.
    func noteIslandActivity() {
        guard settings.activityKeepsAwake else { return }
        guard activity.acquire([.idleSystemSleep], reason: "Mac Island in use") else { return }
        activityUntil = clock().addingTimeInterval(Self.activityHold)
        ensureLoop()
    }

    func tick() {
        let now = clock()
        if let plan, plan.isExpired(at: now) { stop() }
        if let until = activityUntil, now >= until {
            activity.releaseAll()
            activityUntil = nil
        }
        refreshJiggleStatus()
        if isActive, settings.mouseJiggleEnabled, accessibilityTrusted(),
           scheduler.shouldJiggle(now: now, idleSeconds: idleSeconds(),
                                  keepAwakeActive: true, enabled: true) {
            jiggler.jiggle()
            scheduler.didJiggle(at: now)
        }
        stopLoopIfIdle()
    }

    private func refreshJiggleStatus() {
        guard isActive, settings.mouseJiggleEnabled else { jiggleStatus = .off; return }
        jiggleStatus = accessibilityTrusted()
            ? .waiting(intervalMinutes: settings.mouseJiggleIntervalMinutes) : .needsAccessibility
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

    private func stopLoopIfIdle() {
        guard !isActive, activityUntil == nil else { return }
        loop?.cancel()
        loop = nil
    }
}
