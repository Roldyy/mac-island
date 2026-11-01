import Foundation
import Testing
@testable import KeepAwakeFeature

final class FakePower: PowerAssertionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var created: [(id: UInt32, kind: AssertionKind)] = []
    private(set) var released: [UInt32] = []
    private var next: UInt32 = 1
    var failCreate = false
    func create(_ kind: AssertionKind, reason: String) -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        if failCreate { return nil }
        let id = next; next += 1
        created.append((id, kind))
        return id
    }
    func release(_ id: UInt32) { lock.lock(); released.append(id); lock.unlock() }
    var live: Set<UInt32> { Set(created.map(\.id)).subtracting(released) }
}

final class FakeJiggler: MouseJiggling, @unchecked Sendable {
    var count = 0
    func jiggle() { count += 1 }
}

/// In-memory preferences: nothing is ever written to ~/Library/Preferences.
final class MemoryDefaults: KeyValueReading {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

@MainActor
struct Rig {
    let power = FakePower()
    let jig = FakeJiggler()
    let now = Box(Date(timeIntervalSince1970: 1_000_000))
    let idle = Box<TimeInterval>(0)
    let trusted = Box(true)
    let defaults = MemoryDefaults()
    let controller: KeepAwakeController

    init(display: Bool = false, jiggle: Bool = false, activity: Bool = true, intervalMinutes: Int = 1,
         runsLoop: Bool = false) {
        defaults.set(display, forKey: KeepAwakeSettings.preventDisplaySleepKey)
        defaults.set(jiggle, forKey: "keepAwakeMouseJiggleEnabled")
        defaults.set(intervalMinutes, forKey: "keepAwakeMouseJiggleIntervalMinutes")
        defaults.set(activity, forKey: "notchKeepAwakeActivity")
        let n = now, i = idle, t = trusted
        controller = KeepAwakeController(
            power: power, jiggler: jig,
            settings: KeepAwakeSettings(defaults: defaults),
            clock: { n.value }, idleSeconds: { i.value }, accessibilityTrusted: { t.value },
            runsLoop: runsLoop, tickInterval: .milliseconds(10))
    }
}

@Suite @MainActor struct KeepAwakeControllerTests {
    @Test func toggleStartsThenStops() {
        let r = Rig()
        r.controller.toggle()
        #expect(r.controller.isActive && r.power.live.count == 1)
        r.controller.toggle()
        #expect(!r.controller.isActive && r.power.live.isEmpty)
    }

    @Test func startCreatesOneIdleSystemAssertionAndStopReleasesIt() {
        let r = Rig()
        r.controller.start(duration: nil)
        #expect(r.controller.isActive)
        #expect(r.power.created.map(\.kind) == [.idleSystemSleep])
        r.controller.stop()
        #expect(!r.controller.isActive)
        #expect(r.power.live.isEmpty)
        #expect(r.power.released.count == 1)
    }

    @Test func doubleStartIsIdempotent() {
        let r = Rig()
        r.controller.start(duration: nil)
        r.controller.start(duration: 600)
        #expect(r.power.created.count == 1)
        #expect(r.controller.plan?.duration == nil)
    }

    @Test func stopWithoutStartIsSafe() {
        let r = Rig()
        r.controller.stop()
        r.controller.stop()
        #expect(r.power.created.isEmpty)
        #expect(r.power.released.isEmpty)
    }

    @Test func displaySettingAddsADisplayAssertion() {
        let r = Rig(display: true)
        r.controller.start(duration: nil)
        #expect(Set(r.power.created.map(\.kind)) == [.idleSystemSleep, .idleDisplaySleep])
        r.controller.stop()
        #expect(r.power.live.isEmpty)
    }

    @Test func failedCreateLeavesControllerInactive() {
        let r = Rig()
        r.power.failCreate = true
        r.controller.start(duration: nil)
        #expect(!r.controller.isActive)
    }

    @Test func sessionStopsItselfWhenTheDurationEnds() {
        let r = Rig()
        r.controller.start(duration: 1800)
        r.now.value = r.now.value.addingTimeInterval(1799)
        r.controller.tick()
        #expect(r.controller.isActive)
        r.now.value = r.now.value.addingTimeInterval(1)
        r.controller.tick()
        #expect(!r.controller.isActive)
        #expect(r.power.live.isEmpty)
    }

    @Test func deinitReleasesEverything() {
        let power = FakePower()
        do {
            let c = KeepAwakeController(
                power: power, jiggler: FakeJiggler(), settings: KeepAwakeSettings(defaults: MemoryDefaults()),
                clock: { Date() }, idleSeconds: { 0 }, accessibilityTrusted: { true }, runsLoop: false)
            c.start(duration: nil)
            #expect(power.live.count == 1)
        }
        #expect(power.live.isEmpty)
    }

    @Test func jigglesOnlyWhenActiveAndIdleLongEnough() {
        let r = Rig(jiggle: true, intervalMinutes: 1)
        r.idle.value = 600
        r.controller.tick()
        #expect(r.jig.count == 0) // not active
        r.controller.start(duration: nil)
        r.idle.value = 30
        r.controller.tick()
        #expect(r.jig.count == 0)
        r.idle.value = 61
        r.controller.tick()
        #expect(r.jig.count == 1)
        r.controller.tick()
        #expect(r.jig.count == 1) // same instant, no repeat
        r.now.value = r.now.value.addingTimeInterval(60)
        r.controller.tick()
        #expect(r.jig.count == 2)
    }

    @Test func missingAccessibilityBlocksJiggleAndIsReported() {
        let r = Rig(jiggle: true)
        r.trusted.value = false
        r.controller.start(duration: nil)
        r.idle.value = 600
        r.controller.tick()
        #expect(r.jig.count == 0)
        #expect(r.controller.jiggleStatus == .needsAccessibility)
        r.trusted.value = true
        r.controller.tick()
        #expect(r.jig.count == 1)
        #expect(r.controller.jiggleStatus == .waiting(intervalMinutes: 1))
    }

    @Test func jiggleStatusOffWhenDisabled() {
        let r = Rig(jiggle: false)
        r.controller.start(duration: nil)
        r.controller.tick()
        #expect(r.controller.jiggleStatus == .off)
    }

    @Test func islandActivityHoldsAnAssertionThenReleasesIt() {
        let r = Rig(activity: true)
        r.controller.noteIslandActivity()
        #expect(r.power.live.count == 1)
        #expect(!r.controller.isActive) // user-facing session untouched
        r.controller.noteIslandActivity()
        #expect(r.power.created.count == 1) // refresh, not a second assertion
        r.now.value = r.now.value.addingTimeInterval(KeepAwakeController.activityHold + 1)
        r.controller.tick()
        #expect(r.power.live.isEmpty)
    }

    @Test func islandActivityIgnoredWhenSettingIsOff() {
        let r = Rig(activity: false)
        r.controller.noteIslandActivity()
        #expect(r.power.created.isEmpty)
    }

    // The real path: the loop task ticks by itself, nobody calls tick().

    @Test func loopReleasesTheActivityAssertionByItself() async {
        let r = Rig(activity: true, runsLoop: true)
        r.controller.noteIslandActivity()
        #expect(r.power.live.count == 1)
        r.now.value = r.now.value.addingTimeInterval(KeepAwakeController.activityHold + 1)
        #expect(await eventually { r.power.live.isEmpty })
    }

    @Test func loopEndsAnExpiredSessionAndJiggles() async {
        let r = Rig(jiggle: true, intervalMinutes: 1, runsLoop: true)
        r.idle.value = 600
        r.controller.start(duration: 1800)
        #expect(await eventually { r.jig.count >= 1 })
        r.now.value = r.now.value.addingTimeInterval(1800)
        #expect(await eventually { !r.controller.isActive })
        #expect(r.power.live.isEmpty)
    }

    @Test func noLoopMeansNoSelfTick() async {
        let r = Rig(activity: true, runsLoop: false)
        r.controller.noteIslandActivity()
        r.now.value = r.now.value.addingTimeInterval(KeepAwakeController.activityHold + 1)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(r.power.live.count == 1)
    }
}

@MainActor
/// Load tolerant: a failing wait needs BOTH `timeout` of wall clock AND `minimumPolls` turns of the loop. Other
/// main-actor tests can hold the main thread for seconds, so a wall-clock deadline alone expires before the code
/// under test ever got a turn; counting polls guarantees it did.
private func eventually(timeout: TimeInterval = 10, minimumPolls: Int = 300,
                        _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    var polls = 0
    while polls < minimumPolls || Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
        polls += 1
    }
    return condition()
}
