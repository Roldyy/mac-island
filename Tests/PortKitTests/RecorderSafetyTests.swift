import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit

// Lane W4B (recorder): the safety policy and the supervisor, driven through fakes only. Nothing here touches
// ScreenCaptureKit, AVFoundation, a window, a hotkey or the real preferences.

@MainActor
final class FakeRecorderControl: RecorderControlling {
    var state = RecorderState()
    var stopReasons: [String?] = []
    var pauseToggles = 0
    var syncs = 0
    /// A real stop ends the recording at once (the service flips `isRecording` before it finalizes the file).
    var stopEndsRecording = true
    private var handlers: [UUID: @MainActor (RecorderState) -> Void] = [:]

    func emit(_ new: RecorderState) {
        state = new
        for handler in handlers.values { handler(new) }
    }

    func observe(_ handler: @escaping @MainActor (RecorderState) -> Void) -> () -> Void {
        let id = UUID()
        handlers[id] = handler
        return { [weak self] in self?.handlers[id] = nil }
    }

    var observerCount: Int { handlers.count }

    func stop(reason: String?) {
        stopReasons.append(reason)
        if stopEndsRecording { emit(RecorderState()) }
    }

    func togglePause() { pauseToggles += 1 }
    func syncWithPreferences() { syncs += 1 }
}

@MainActor
final class FakeIsland {
    var posted: [IslandActivity] = []
    var withdrawn: [String] = []
    var poster: RecorderIslandPoster {
        RecorderIslandPoster(post: { [self] activity, _ in posted.append(activity) },
                             withdraw: { [self] id in withdrawn.append(id) })
    }
}

@MainActor
final class FakeStatusItem: RecorderStatusPresenting {
    var shown: [(elapsed: String, paused: Bool)] = []
    var hides = 0
    var actions: RecorderStatusActions?
    func show(elapsed: String, paused: Bool, actions: RecorderStatusActions) {
        shown.append((elapsed, paused))
        self.actions = actions
    }
    func hide() { hides += 1 }
}

@MainActor
final class FakeStopHotkey: RecorderStopHotkeying {
    var registers = 0
    var unregisters = 0
    var accepts = true
    private var onPress: (@MainActor () -> Void)?
    func register(onPress: @escaping @MainActor () -> Void) -> Bool {
        registers += 1
        guard accepts else { return false }
        self.onPress = onPress
        return true
    }
    func unregister() { unregisters += 1; onPress = nil }
    func press() { onPress?() }
    var isRegistered: Bool { onPress != nil }
}

@MainActor
final class FakeSystemEvents: RecorderSystemEventSource {
    private var handler: (@MainActor (RecorderSystemEvent) -> Void)?
    var observing: Bool { handler != nil }
    func observe(_ handler: @escaping @MainActor (RecorderSystemEvent) -> Void) -> () -> Void {
        self.handler = handler
        return { [weak self] in self?.handler = nil }
    }
    func fire(_ event: RecorderSystemEvent) { handler?(event) }
}

/// A supervisor wired to fakes, with a free-space reading and a clock the test moves.
@MainActor
final class SafetyRig {
    let control = FakeRecorderControl()
    let island = FakeIsland()
    let status = FakeStatusItem()
    let hotkey = FakeStopHotkey()
    let events = FakeSystemEvents()
    let free = Box<Int64?>(50_000_000_000)
    let now = Box(Date(timeIntervalSince1970: 1_800_000_000))
    let bench = TestDefaults.make()
    private(set) var safety: RecorderSafety!

    init() {
        let free = free
        let now = now
        let defaults = bench.defaults
        safety = RecorderSafety(control: control, dependencies: .init(
            island: island.poster, statusItem: status, hotkey: hotkey, events: events,
            freeBytes: { free.value }, now: { now.value }, defaults: { defaults }))
    }

    func cleanup() { bench.cleanup() }

    func recording(_ seconds: Int, paused: Bool = false) -> RecorderState {
        RecorderState(isRecording: true, isPaused: paused, elapsedSeconds: seconds)
    }
}

@MainActor
@Suite(.serialized) struct RecorderSafetyTests {
    // MARK: Policy tables

    @Test func theMaximumDurationIsClampedToTheAllowedChoices() {
        #expect(RecorderSafetyPolicy.allowedMaxMinutes == [5, 15, 30, 60, 120])
        #expect(RecorderSafetyPolicy.sanitizedMaxMinutes(0) == 60 && RecorderSafetyPolicy.sanitizedMaxMinutes(-3) == 60,
                "nothing stored: the default")
        #expect(RecorderSafetyPolicy.sanitizedMaxMinutes(5) == 5 && RecorderSafetyPolicy.sanitizedMaxMinutes(120) == 120)
        #expect(RecorderSafetyPolicy.sanitizedMaxMinutes(45) == 60, "between two choices: the next one up")
        #expect(RecorderSafetyPolicy.sanitizedMaxMinutes(100_000) == 120, "never unlimited")
    }

    @Test func theStopReasonTable() {
        func reason(elapsed: Int = 10, max: Int = 60, free: Int64? = 5_000_000_000, paused: Int = 0) -> RecorderSafetyPolicy.StopReason? {
            RecorderSafetyPolicy.stopReason(elapsedSeconds: elapsed, maxMinutes: max, freeBytes: free, pausedSeconds: paused)
        }
        #expect(reason() == nil)
        #expect(reason(elapsed: 3599) == nil && reason(elapsed: 3600) == .maxDuration)
        #expect(reason(elapsed: 300, max: 5) == .maxDuration)
        #expect(reason(free: 999_999_999) == .lowDisk && reason(free: 1_000_000_000) == nil, "under 1 GB, not at 1 GB")
        #expect(reason(free: nil) == nil, "no reading yet is no reason")
        #expect(reason(paused: 1799) == nil && reason(paused: 1800) == .pausedTooLong)
        #expect(reason(elapsed: 99_999, free: 10) == .lowDisk, "a full disk wins over everything")
    }

    @Test func theLowDiskFloorIsStricterThanTheUpstreamOne() {
        #expect(RecorderSafetyPolicy.minimumFreeBytes == 1_000_000_000)
        #expect(RecorderSafetyPolicy.minimumFreeBytes > RecorderSupport.minimumFreeBytesToContinue)
        #expect(RecorderSafetyPolicy.minimumFreeBytes < RecorderSupport.minimumFreeBytesToStart,
                "a recording that could start does not stop at once")
    }

    @Test func everyStopMessageIsFrenchAndSaysTheVideoIsSaved() {
        for reason in [RecorderSafetyPolicy.StopReason.maxDuration, .lowDisk, .pausedTooLong, .displaySleep, .screenLocked] {
            #expect(reason.message.hasPrefix("Enregistrement arrêté"), "\(reason)")
            #expect(reason.message.hasSuffix("La vidéo est enregistrée."), "\(reason)")
        }
    }

    @Test func theSettingsReadFromTheHostDefaults() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        #expect(RecorderSafetyKeys.maxMinutes(in: bench.defaults) == 60)
        #expect(RecorderSafetyKeys.stopsOnSleepOrLock(in: bench.defaults), "on until the person turns it off")
        bench.defaults.set(15, forKey: RecorderSafetyKeys.maxMinutes)
        bench.defaults.set(false, forKey: RecorderSafetyKeys.stopOnSleepOrLock)
        #expect(RecorderSafetyKeys.maxMinutes(in: bench.defaults) == 15)
        #expect(!RecorderSafetyKeys.stopsOnSleepOrLock(in: bench.defaults))
    }

    // MARK: The indicator

    @Test func theIslandItemIsAnAlertWithARedDotAndTheElapsedTime() {
        let item = RecorderSafetyPolicy.islandActivity(elapsedSeconds: 75, paused: false)
        #expect(item.id == "screenRecorder.recording" && item.source == "screenRecorder")
        #expect(item.priority == .alert && item.showsDot)
        #expect(item.leading?.text == "Enregistrement 1:15" && item.leading?.status == .danger)
        #expect(item.leading?.symbol == "record.circle.fill")
        let paused = RecorderSafetyPolicy.islandActivity(elapsedSeconds: 75, paused: true)
        #expect(paused.leading?.status == .warning && paused.leading?.text?.contains("pause") == true)
    }

    @Test func aRecordingPostsTheIndicatorEverySecondAndWithdrawsItWhenItEnds() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        #expect(r.island.posted.isEmpty && r.status.shown.isEmpty && !r.hotkey.isRegistered, "armed is not recording")
        r.control.emit(r.recording(0))
        r.control.emit(r.recording(1))
        r.control.emit(r.recording(2))
        #expect(r.island.posted.count == 3)
        #expect(r.island.posted.map { $0.leading?.text } == ["Enregistrement 0:00", "Enregistrement 0:01", "Enregistrement 0:02"])
        #expect(r.island.posted.allSatisfy { $0.priority == .alert && $0.showsDot })
        #expect(r.status.shown.map(\.elapsed) == ["0:00", "0:01", "0:02"])
        #expect(r.hotkey.registers == 1 && r.hotkey.isRegistered, "one registration for the whole recording")
        r.control.emit(RecorderState())
        #expect(r.island.withdrawn == ["screenRecorder.recording"])
        #expect(r.status.hides == 1 && r.hotkey.unregisters == 1 && !r.hotkey.isRegistered)
        r.control.emit(RecorderState())
        #expect(r.island.withdrawn.count == 1 && r.status.hides == 1, "ending twice takes nothing down twice")
    }

    @Test func aRecordingAlreadyRunningWhenTheSupervisorArmsShowsItsSignsAtOnce() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.control.state = r.recording(40)
        r.safety.arm()
        #expect(r.island.posted.count == 1 && r.status.shown.count == 1 && r.hotkey.isRegistered)
    }

    @Test func pausingShowsThePausedSignsAndTheMenuActionsReachTheRecorder() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        r.control.emit(r.recording(5, paused: true))
        #expect(r.status.shown.last?.paused == true)
        #expect(r.island.posted.last?.leading?.status == .warning)
        r.status.actions?.togglePause()
        #expect(r.control.pauseToggles == 1)
        r.status.actions?.stop()
        #expect(r.control.stopReasons.count == 1 && r.control.stopReasons[0] == nil, "a stop of the person's saves normally")
    }

    @Test func theGlobalShortcutStopsTheRecordingAndGoesAwayWithIt() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        r.control.emit(r.recording(3))
        #expect(r.hotkey.isRegistered)
        r.hotkey.press()
        #expect(r.control.stopReasons.count == 1 && r.control.stopReasons[0] == nil)
        #expect(!r.hotkey.isRegistered && r.island.withdrawn.count == 1, "stopped: every sign is down")
    }

    @Test func aRefusedShortcutDoesNotHideTheOtherSigns() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.hotkey.accepts = false
        r.safety.arm()
        r.control.emit(r.recording(1))
        #expect(r.hotkey.registers == 1 && !r.hotkey.isRegistered)
        #expect(r.island.posted.count == 1 && r.status.shown.count == 1, "island and menu bar still say it is recording")
    }

    // MARK: Automatic stops

    @Test func theMaximumDurationStopsOnceAndSavesWithItsMessage() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.bench.defaults.set(5, forKey: RecorderSafetyKeys.maxMinutes)
        r.control.stopEndsRecording = false
        r.safety.arm()
        r.control.emit(r.recording(299))
        #expect(r.control.stopReasons.isEmpty)
        r.control.emit(r.recording(300))
        r.control.emit(r.recording(301))
        #expect(r.control.stopReasons == [RecorderSafetyPolicy.StopReason.maxDuration.message], "asked once while it finishes")
    }

    @Test func theDefaultMaximumIsOneHour() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.control.stopEndsRecording = false
        r.safety.arm()
        r.control.emit(r.recording(3599))
        #expect(r.control.stopReasons.isEmpty)
        r.control.emit(r.recording(3600))
        #expect(r.control.stopReasons.count == 1)
    }

    @Test func lowDiskStopsTheRecordingAndEnoughRoomDoesNot() async {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        r.control.emit(r.recording(10))
        r.free.value = 1_000_000_000
        await r.safety.checkDisk()
        #expect(r.control.stopReasons.isEmpty, "exactly 1 GB is enough")
        r.free.value = nil
        await r.safety.checkDisk()
        #expect(r.control.stopReasons.isEmpty, "no reading is no reason")
        r.free.value = 700_000_000
        await r.safety.checkDisk()
        #expect(r.control.stopReasons == [RecorderSafetyPolicy.StopReason.lowDisk.message])
        #expect(r.island.withdrawn.count == 1, "and the signs come down with the recording")
    }

    @Test func aDiskReadingThatLandsAfterTheRecordingEndedIsIgnored() async {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        r.control.emit(r.recording(10))
        r.control.emit(RecorderState())
        r.free.value = 10
        await r.safety.checkDisk()
        #expect(r.control.stopReasons.isEmpty)
        r.control.emit(r.recording(1))  // not a multiple of 5: no reading is scheduled by the update itself
        await r.safety.checkDisk(token: -1)
        #expect(r.control.stopReasons.isEmpty, "a reading asked for an older recording says nothing about this one")
    }

    @Test func aPausedRecordingIsStoppedAfterThirtyMinutes() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.control.stopEndsRecording = false
        r.safety.arm()
        r.control.emit(r.recording(20, paused: true))
        r.now.value = r.now.value.addingTimeInterval(1799)
        r.control.emit(r.recording(20, paused: true))
        #expect(r.control.stopReasons.isEmpty)
        r.now.value = r.now.value.addingTimeInterval(2)
        r.control.emit(r.recording(20, paused: true))
        #expect(r.control.stopReasons == [RecorderSafetyPolicy.StopReason.pausedTooLong.message])
    }

    @Test func resumingResetsThePauseClock() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.control.stopEndsRecording = false
        r.safety.arm()
        r.control.emit(r.recording(20, paused: true))
        r.now.value = r.now.value.addingTimeInterval(1700)
        r.control.emit(r.recording(21, paused: false))
        r.control.emit(r.recording(22, paused: true))
        r.now.value = r.now.value.addingTimeInterval(1700)
        r.control.emit(r.recording(22, paused: true))
        #expect(r.control.stopReasons.isEmpty, "two pauses of 28 minutes are not one of 56")
    }

    @Test func displaySleepAndScreenLockStopWhenTheyAreChosenAndOnlyWhileRecording() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        r.events.fire(.displaySleep)
        #expect(r.control.stopReasons.isEmpty, "nothing is recording")
        r.control.emit(r.recording(8))
        r.events.fire(.displaySleep)
        #expect(r.control.stopReasons == [RecorderSafetyPolicy.StopReason.displaySleep.message])
        r.control.emit(r.recording(0))
        r.events.fire(.screenLocked)
        #expect(r.control.stopReasons.last == RecorderSafetyPolicy.StopReason.screenLocked.message)
    }

    @Test func theSleepStopCanBeSwitchedOff() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.bench.defaults.set(false, forKey: RecorderSafetyKeys.stopOnSleepOrLock)
        r.safety.arm()
        r.control.emit(r.recording(8))
        r.events.fire(.displaySleep)
        r.events.fire(.screenLocked)
        #expect(r.control.stopReasons.isEmpty)
    }

    // MARK: Disarm

    @Test func disarmTakesEverySignDownAndStopsListening() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        r.control.emit(r.recording(4))
        #expect(r.control.observerCount == 1 && r.events.observing)
        r.safety.disarm()
        #expect(r.island.withdrawn == ["screenRecorder.recording"])
        #expect(r.status.hides == 1 && r.hotkey.unregisters == 1)
        #expect(r.control.observerCount == 0 && !r.events.observing && !r.safety.isArmed)
        let posts = r.island.posted.count
        r.control.emit(r.recording(5))
        #expect(r.island.posted.count == posts, "disarmed: a later reading shows nothing")
        r.safety.disarm()
        #expect(r.island.withdrawn.count == 1, "idempotent")
    }

    @Test func armingTwiceObservesOnce() {
        let r = SafetyRig()
        defer { r.cleanup() }
        r.safety.arm()
        r.safety.arm()
        #expect(r.control.observerCount == 1)
    }

    // MARK: GIF frame maths (upstream, pure)

    @Test func gifFrameCountAndOutputSize() {
        #expect(RecorderSupport.gifFrameCount(duration: 2.5, fps: 12) == 30)
        #expect(RecorderSupport.gifFrameCount(duration: 0.01, fps: 8) == 1, "at least one frame")
        #expect(RecorderSupport.gifFrameCount(duration: 0, fps: 12) == 0)
        #expect(RecorderSupport.gifFrameCount(duration: .infinity, fps: 12) == 0)
        #expect(RecorderSupport.gifFrameCount(duration: 3, fps: 0) == 0)
        #expect(RecorderSupport.sanitizedGIFFrameRate(7) == 12 && RecorderSupport.sanitizedGIFFrameRate(15) == 15)
        for size in RecorderSupport.GIFSize.allCases {
            let out = RecorderSupport.gifOutputSize(source: CGSize(width: 3840, height: 2160), size: size)
            #expect(max(out.width, out.height) <= size.longEdge, "\(size)")
            #expect(Int(out.width) % 2 == 0 && Int(out.height) % 2 == 0, "\(size): even sides")
        }
        let small = RecorderSupport.gifOutputSize(source: CGSize(width: 200, height: 100), size: .large)
        #expect(small.width == 200 && small.height == 100, "never enlarged")
    }
}
