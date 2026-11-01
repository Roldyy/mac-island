import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// A tap that is only a list of calls: the manager is driven through `send`, with no permission, no window and no
/// real event.
final class FakeCleaningTap: CleaningEventTapping {
    private var deliver: ((CleaningInput) -> Bool)?
    var refuses = false
    var enabled = true
    private(set) var started = 0
    private(set) var stopped = 0
    var isEnabled: Bool { enabled }

    func start(deliver: @escaping (CleaningInput) -> Bool) -> Bool {
        if refuses { return false }
        started += 1
        self.deliver = deliver
        return true
    }

    func stop() {
        stopped += 1
        deliver = nil
    }

    /// What the system would do with this event: true = swallowed. A stopped tap swallows nothing.
    @discardableResult func send(_ input: CleaningInput) -> Bool { deliver?(input) ?? false }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var uptime: TimeInterval = 5_000
    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        uptime += seconds
    }
}

/// One manager wired to fakes.
@MainActor
private struct Rig {
    let manager: CleaningModeManager
    let tap = FakeCleaningTap()
    let clock = Clock()
    let trusted = Box(true)
    let allowed = Box(true)
    let log = Box<[String]>([])
    let center = NotificationCenter()

    init(allowed isAllowed: (@Sendable () -> Bool)? = nil) {
        let tap = tap, clock = clock, trusted = trusted, allowed = allowed, log = log
        manager = CleaningModeManager(environment: .init(
            makeTap: { tap },
            now: { clock.now },
            uptime: { clock.uptime },
            isTrusted: { trusted.value },
            isAllowed: { isAllowed?() ?? allowed.value },
            showOverlays: { _ in log.value.append("show") },
            hideOverlays: { _ in log.value.append("hide") },
            suspendOthers: { log.value.append("suspend") },
            resumeOthers: { log.value.append("resume") },
            guideToAccessibility: { log.value.append("guide") },
            runsTimer: false,
            notifications: center))
    }

    func ends() -> CleaningEnd? { manager.lastEnd }

    /// Lets the main-queue hop of a user unlock run.
    func settle() async { try? await Task.sleep(for: .milliseconds(60)) }
}

@MainActor
@Suite(.serialized) struct InputShortcutsCleaningTests {
    // MARK: Start

    @Test func startsOnlyWithTheRegistryAndAccessibilityAndNeverPrompts() {
        let r = Rig()
        r.allowed.value = false
        #expect(r.manager.activate(guideWhenMissing: false) == .featureOff)
        r.allowed.value = true
        r.trusted.value = false
        #expect(r.manager.activate(guideWhenMissing: false) == .needsAccessibility)
        #expect(r.log.value.isEmpty, "no alert, no overlay, nothing suspended when it cannot start")
        #expect(r.tap.started == 0 && !r.manager.isActive)
        #expect(r.manager.activate(guideWhenMissing: true) == .needsAccessibility)
        #expect(r.log.value == ["guide"], "the alert only opens System Settings; no system prompt")
    }

    @Test func aTapTheSystemRefusesSwallowsNothing() {
        let r = Rig()
        r.tap.refuses = true
        #expect(r.manager.activate() == .refused)
        #expect(!r.manager.isActive && r.log.value.isEmpty)
    }

    @Test func startingTwiceKeepsOneTap() {
        let r = Rig()
        #expect(r.manager.activate() == .started)
        #expect(r.manager.activate() == .alreadyRunning)
        #expect(r.tap.started == 1)
        #expect(r.log.value == ["suspend", "show"])
    }

    // MARK: What is swallowed

    @Test func keysScrollAndSystemKeysAreSwallowedClicksAreNot() {
        let r = Rig()
        r.manager.activate()
        #expect(r.tap.send(.key(code: 0, isDown: true, isRepeat: false)))
        #expect(r.tap.send(.key(code: 0, isDown: false, isRepeat: false)))
        #expect(r.tap.send(.flagsChanged(code: 55)))
        #expect(r.tap.send(.systemKey(CleaningSystemKeyEvent(code: 10_000, isKeyDown: true, isRepeat: false))))
        #expect(r.tap.send(.other))
        #expect(!r.tap.send(.mouseButton(button: 0, isDown: true)))
        #expect(!r.tap.send(.mouseButton(button: 0, isDown: false)))
    }

    // MARK: Every way out

    @Test func endsByItselfAfterSixtySeconds() {
        let r = Rig()
        r.manager.activate()
        r.clock.advance(59); r.manager.tick()
        #expect(r.manager.isActive && r.manager.remainingSeconds == 1)
        r.clock.advance(1); r.manager.tick()
        #expect(!r.manager.isActive && r.ends() == .timeout)
        #expect(r.tap.stopped == 1)
        #expect(r.log.value == ["suspend", "show", "hide", "resume"], "the other services come back")
        #expect(!r.tap.send(.key(code: 0, isDown: true, isRepeat: false)), "a stopped tap swallows nothing")
    }

    @Test func theTapCallbackStopsSwallowingPastTheDeadlineEvenIfTheTimerNeverFires() {
        let r = Rig()
        r.manager.activate()
        r.clock.uptime += 59.9
        #expect(r.tap.send(.key(code: 0, isDown: true, isRepeat: false)))
        r.clock.uptime += 0.2
        #expect(!r.tap.send(.key(code: 0, isDown: true, isRepeat: false)), "past 60 s the event goes through")
        #expect(!r.manager.isActive && r.ends() == .timeout && r.tap.stopped == 1)
    }

    @Test func endsWhenEscapeIsHeldThreeSeconds() {
        let r = Rig()
        r.manager.activate()
        r.clock.advance(5)
        r.tap.send(.key(code: 53, isDown: true, isRepeat: false))
        r.clock.advance(1.5)
        r.tap.send(.key(code: 53, isDown: true, isRepeat: true))  // a repeat never restarts the hold
        r.clock.advance(1.4); r.manager.tick()
        #expect(r.manager.isActive)
        r.clock.advance(0.1); r.manager.tick()
        #expect(!r.manager.isActive && r.ends() == .escapeHeld && r.tap.stopped == 1)
    }

    @Test func aShortEscapeDoesNotEndIt() {
        let r = Rig()
        r.manager.activate()
        r.tap.send(.key(code: 53, isDown: true, isRepeat: false))
        r.clock.advance(1)
        r.tap.send(.key(code: 53, isDown: false, isRepeat: false))
        r.clock.advance(10); r.manager.tick()
        #expect(r.manager.isActive)
    }

    @Test func fiveEscapePressesUnlock() async {
        let r = Rig()
        r.manager.activate()
        for _ in 0..<4 { r.tap.send(.key(code: 53, isDown: true, isRepeat: false)) }
        #expect(r.manager.unlockProgress == 4 && r.manager.isActive)
        r.tap.send(.key(code: 0, isDown: true, isRepeat: false))  // any other key resets the count
        #expect(r.manager.unlockProgress == 0)
        for _ in 0..<5 { r.tap.send(.key(code: 53, isDown: true, isRepeat: false)) }
        await r.settle()
        #expect(!r.manager.isActive && r.ends() == .unlocked && r.tap.stopped == 1)
    }

    @Test func theUnlockButtonWaitsForAClickInProgressButForcedEndsDoNot() async {
        let r = Rig()
        r.manager.activate()
        r.tap.send(.mouseButton(button: 0, isDown: true))
        r.manager.deactivate()  // the button on the overlay
        await r.settle()
        #expect(r.manager.isActive, "a click begun under the lock finishes before the tap goes")
        r.tap.send(.mouseButton(button: 0, isDown: false))
        await r.settle()
        #expect(!r.manager.isActive && r.ends() == .unlocked)

        // 60 s is absolute: a button held down does not postpone it.
        r.manager.activate()
        r.tap.send(.mouseButton(button: 1, isDown: true))
        r.clock.advance(60); r.manager.tick()
        #expect(!r.manager.isActive && r.ends() == .timeout)
    }

    @Test func endsAtOnceWhenTheSystemDisablesTheTap() {
        let r = Rig()
        r.manager.activate()
        #expect(!r.tap.send(.tapDisabled), "the event itself goes through")
        #expect(!r.manager.isActive && r.ends() == .tapFailed && r.tap.stopped == 1)
        #expect(r.log.value.suffix(2) == ["hide", "resume"])
    }

    @Test func endsWhenTheTapIsSwitchedOffBehindOurBackOrAccessibilityGoes() {
        let r = Rig()
        r.manager.activate()
        r.tap.enabled = false
        r.manager.tick()
        #expect(!r.manager.isActive && r.ends() == .tapFailed)

        r.tap.enabled = true
        r.manager.activate()
        r.trusted.value = false
        r.manager.tick()
        #expect(!r.manager.isActive && r.ends() == .tapFailed)
    }

    @Test func endsWhenTheAppQuits() {
        let r = Rig()
        r.manager.activate()
        r.center.post(name: NSApplication.willTerminateNotification, object: nil)
        // The observer is delivered on the main queue.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(!r.manager.isActive && r.ends() == .quit && r.tap.stopped == 1)

        r.manager.activate()
        r.manager.stop(.quit)
        r.manager.stop(.quit)
        #expect(r.tap.stopped == 2, "stop is idempotent: one tap removal per period")
    }

    // MARK: The registry

    @Test func theKillSwitchSafeModeAndTheSwitchAllEndIt() {
        PortHostFixture.isolated { defaults in
            let r = Rig(allowed: { AppFeature.cleaningMode.isAvailable })
            let saved = PortCleaningMode.manager
            PortCleaningMode.manager = r.manager
            defer { PortCleaningMode.manager = saved }

            let binding = PortFeatureBinding(permissions: { PortPermissionState(accessibility: true) })
            InputShortcutsLane.bind(into: binding)
            let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
            let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: defaults,
                                           crashMarker: marker, withdraw: { _ in })
            binding.connectAvailability()
            registry.launch(starters: binding.starters, stoppers: binding.stoppers)

            #expect(r.manager.activate(guideWhenMissing: false) == .featureOff, "off until the registry says on")
            registry.switches["cleaningMode"] = true
            #expect(r.manager.activate(guideWhenMissing: false) == .started)

            registry.killSwitch = true
            #expect(!r.manager.isActive && r.ends() == .stopped, "the kill switch ends the lock")
            #expect(r.manager.activate(guideWhenMissing: false) == .featureOff, "and nothing starts while it is on")
            registry.killSwitch = false

            #expect(r.manager.activate(guideWhenMissing: false) == .started)
            registry.safeMode = true
            #expect(!r.manager.isActive && r.ends() == .stopped, "safe mode ends the lock (the category is not daily)")
            registry.safeMode = false

            #expect(r.manager.activate(guideWhenMissing: false) == .started)
            registry.switches["cleaningMode"] = false
            #expect(!r.manager.isActive && r.ends() == .stopped, "switching the feature off ends the lock")
        }
    }

    // MARK: Crash recovery

    @Test func theLockWritesNothingToDiskSoACrashHasNothingToRecover() {
        PortHostFixture.isolated { defaults in
            let before = defaults.dictionaryRepresentation().keys.sorted()
            let r = Rig()
            r.manager.activate()
            r.clock.advance(10)
            r.manager.tick()
            r.manager.stop(.quit)
            #expect(defaults.dictionaryRepresentation().keys.sorted() == before)
            #expect(PortBridge.RecoveryPlan(defaults: defaults) == PortBridge.RecoveryPlan(defaults: TestDefaults.make().defaults),
                    "no marker: the launch recovery has nothing to enter")
        }
    }
}

@Suite struct InputShortcutsCleaningPolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func runsUntilSixtySeconds() {
        var p = CleaningPolicy(start: t0)
        #expect(p.tick(at: t0.addingTimeInterval(59.9)) == nil)
        #expect(p.tick(at: t0.addingTimeInterval(60)) == .timeout)
        #expect(!p.isRunning)
    }

    @Test func remainingCountsDownAndRoundsUp() {
        let p = CleaningPolicy(start: t0)
        #expect(p.remainingSeconds(at: t0) == 60)
        #expect(p.remainingSeconds(at: t0.addingTimeInterval(15)) == 45)
        #expect(p.remainingSeconds(at: t0.addingTimeInterval(15.2)) == 45)
        #expect(p.remainingSeconds(at: t0.addingTimeInterval(500)) == 0)
    }

    @Test func escapeHeldThreeSecondsEndsAndARepeatDoesNotRestartIt() {
        var p = CleaningPolicy(start: t0)
        p.escape(down: true, isRepeat: false, at: t0.addingTimeInterval(10))
        p.escape(down: true, isRepeat: true, at: t0.addingTimeInterval(11))
        #expect(p.tick(at: t0.addingTimeInterval(12.9)) == nil)
        #expect(p.tick(at: t0.addingTimeInterval(13)) == .escapeHeld)
    }

    @Test func firstReasonWins() {
        var p = CleaningPolicy(start: t0)
        p.end(.tapFailed)
        p.end(.quit)
        #expect(p.tick(at: t0.addingTimeInterval(100)) == .tapFailed)
    }

    @Test func tapDeadlineLetsInputThrough() {
        #expect(CleaningPolicy.swallows(uptime: 99, deadline: 100))
        #expect(!CleaningPolicy.swallows(uptime: 100, deadline: 100))
    }
}
