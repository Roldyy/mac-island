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

/// The two-minute hold the island takes while it is in use: the one piece of the old controller the ported
/// manager does not do. IOKit, the clock and the preference are fakes.
@Suite @MainActor struct IslandActivityHoldTests {
    @MainActor struct Rig {
        let power = FakePower()
        let now = Box(Date(timeIntervalSince1970: 1_000_000))
        let hold: IslandActivityHold

        init(activity: Bool = true, runsLoop: Bool = false) {
            let defaults = MemoryDefaults()
            defaults.set(activity, forKey: "notchKeepAwakeActivity")
            let n = now
            hold = IslandActivityHold(power: power, settings: KeepAwakeSettings(defaults: defaults),
                                      clock: { n.value }, runsLoop: runsLoop, tickInterval: .milliseconds(10))
        }
    }

    @Test func holdsOneIdleSystemAssertionThenReleasesItAfterTwoMinutes() {
        let r = Rig()
        r.hold.note()
        #expect(r.power.created.map(\.kind) == [.idleSystemSleep])
        #expect(r.hold.isHolding)
        r.now.value = r.now.value.addingTimeInterval(IslandActivityHold.holdDuration - 1)
        r.hold.tick()
        #expect(r.power.live.count == 1)
        r.now.value = r.now.value.addingTimeInterval(1)
        r.hold.tick()
        #expect(r.power.live.isEmpty && !r.hold.isHolding)
    }

    @Test func aSecondNoteRefreshesTheDeadlineInsteadOfCreatingAnotherAssertion() {
        let r = Rig()
        r.hold.note()
        r.now.value = r.now.value.addingTimeInterval(100)
        r.hold.note()
        #expect(r.power.created.count == 1)
        r.now.value = r.now.value.addingTimeInterval(100)  // 200 s after the first note, 100 after the second
        r.hold.tick()
        #expect(r.power.live.count == 1)
    }

    @Test func ignoredWhenThePreferenceIsOff() {
        let r = Rig(activity: false)
        r.hold.note()
        #expect(r.power.created.isEmpty && !r.hold.isHolding)
    }

    @Test func aFailedAssertionLeavesNothingHeld() {
        let r = Rig()
        r.power.failCreate = true
        r.hold.note()
        #expect(!r.hold.isHolding)
    }

    @Test func releaseIsSafeWithoutANote() {
        let r = Rig()
        r.hold.release()
        #expect(r.power.created.isEmpty && r.power.released.isEmpty)
    }

    @Test func deinitReleasesEverything() {
        let power = FakePower()
        do {
            let hold = IslandActivityHold(power: power, settings: KeepAwakeSettings(defaults: MemoryDefaults()),
                                          clock: { Date() }, runsLoop: false)
            hold.note()
            #expect(power.live.count == 1)
        }
        #expect(power.live.isEmpty)
    }

    @Test func theLoopReleasesTheAssertionByItself() async {
        let r = Rig(runsLoop: true)
        r.hold.note()
        #expect(r.power.live.count == 1)
        r.now.value = r.now.value.addingTimeInterval(IslandActivityHold.holdDuration + 1)
        let end = Date().addingTimeInterval(3)
        while Date() < end, !r.power.live.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(r.power.live.isEmpty)
    }
}
