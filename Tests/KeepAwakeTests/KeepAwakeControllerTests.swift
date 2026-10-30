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

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

@MainActor
struct Rig {
    let power = FakePower()
    let jig = FakeJiggler()
    let now = Box(Date(timeIntervalSince1970: 1_000_000))
    let idle = Box<TimeInterval>(0)
    let trusted = Box(true)
    let defaults: UserDefaults
    let controller: KeepAwakeController

    init(display: Bool = false, jiggle: Bool = false, activity: Bool = true, intervalMinutes: Int = 1) {
        let name = "ka-ctrl-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(display, forKey: KeepAwakeSettings.preventDisplaySleepKey)
        defaults.set(jiggle, forKey: "keepAwakeMouseJiggleEnabled")
        defaults.set(intervalMinutes, forKey: "keepAwakeMouseJiggleIntervalMinutes")
        defaults.set(activity, forKey: "notchKeepAwakeActivity")
        let n = now, i = idle, t = trusted
        controller = KeepAwakeController(
            power: power, jiggler: jig,
            settings: KeepAwakeSettings(defaults: defaults),
            clock: { n.value }, idleSeconds: { i.value }, accessibilityTrusted: { t.value },
            runsLoop: false)
    }
}

@Suite @MainActor struct KeepAwakeControllerTests {
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
            let name = "ka-deinit-\(UUID().uuidString)"
            let d = UserDefaults(suiteName: name)!
            let c = KeepAwakeController(
                power: power, jiggler: FakeJiggler(), settings: KeepAwakeSettings(defaults: d),
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
}
