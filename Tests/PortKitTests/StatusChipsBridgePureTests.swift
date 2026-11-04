import Foundation
import ShellKit
import Testing
@testable import PortKit

/// MIS_0102: the pure half of the status-chip bridge: thresholds, French text, the Quit refusal list, the device
/// order and the timer's progress. No service, no hardware.
@Suite struct StatusChipsBridgePureTests {
    // MARK: Battery health

    @Test(arguments: [
        (100.0, StatusChipReading.Level.normal), (80.0, .normal), (79.5, .normal),
        (79.4, .attention), (70.0, .attention), (69.5, .attention), (69.4, .alert), (40.0, .alert),
    ])
    func batteryLevelFollowsTheShownValue(health: Double, level: StatusChipReading.Level) {
        #expect(BatteryHealthChip.level(health: health) == level)
    }

    @Test func batteryTextOnBatteryWithTimeLeft() throws {
        let sample = BatteryHealthSample(healthPercent: 91.6, cycleCount: 312, timeRemaining: 3 * 3600 + 20 * 60)
        let reading = try #require(BatteryHealthChip.reading(sample, openMonitor: nil))
        #expect(reading.kind == .batteryHealth)
        #expect(reading.primary == "92 % santé")
        #expect(reading.secondary == "312 cycles · 3 h 20 min")
        #expect(reading.level == .normal)
        #expect(reading.actions.isEmpty)
    }

    @Test func batteryTextPluggedIn() throws {
        let sample = BatteryHealthSample(healthPercent: 78, cycleCount: 1, externalConnected: true)
        let reading = try #require(BatteryHealthChip.reading(sample, openMonitor: {}))
        #expect(reading.secondary == "1 cycle · branchée")
        #expect(reading.level == .attention)
        #expect(reading.actions.map(\.title) == ["Ouvrir le Moniteur"])
    }

    @Test func batteryTextWithoutTimeEstimate() throws {
        let sample = BatteryHealthSample(healthPercent: 65, cycleCount: 800)
        let reading = try #require(BatteryHealthChip.reading(sample, openMonitor: nil))
        #expect(reading.secondary == "800 cycles · sur batterie")
        #expect(reading.level == .alert)
    }

    @Test func batteryFallsBackToCyclesAndThenToNoChip() throws {
        let cyclesOnly = try #require(BatteryHealthChip.reading(BatteryHealthSample(cycleCount: 40), openMonitor: nil))
        #expect(cyclesOnly.primary == "40 cycles")
        #expect(cyclesOnly.secondary == "sur batterie")
        #expect(BatteryHealthChip.reading(BatteryHealthSample(), openMonitor: nil) == nil)
    }

    // MARK: Formatting

    @Test func durationAndCountdownText() {
        #expect(StatusChipBridgeFormat.duration(45 * 60) == "45 min")
        #expect(StatusChipBridgeFormat.duration(2 * 3600) == "2 h")
        #expect(StatusChipBridgeFormat.duration(0) == "0 min")
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(StatusChipBridgeFormat.countdown(until: now.addingTimeInterval(11 * 60 + 20), now: now) == "dans 12 min")
        #expect(StatusChipBridgeFormat.countdown(until: now.addingTimeInterval(1), now: now) == "dans 1 min")
        #expect(StatusChipBridgeFormat.countdown(until: now.addingTimeInterval(65 * 60), now: now) == "dans 1 h 05")
        #expect(StatusChipBridgeFormat.countdown(until: now.addingTimeInterval(120 * 60), now: now) == "dans 2 h")
        #expect(StatusChipBridgeFormat.countdown(until: now, now: now) == "maintenant")
    }

    @Test func truncationKeepsShortTextAndCapsLongText() {
        #expect(StatusChipBridgeFormat.truncated("  Point hebdo ", limit: 24) == "Point hebdo")
        let long = String(repeating: "a", count: 30)
        let cut = StatusChipBridgeFormat.truncated(long, limit: 24)
        #expect(cut.count == 24)
        #expect(cut.hasSuffix("…"))
        #expect(StatusChipBridgeFormat.truncated(String(repeating: "b", count: 24), limit: 24).count == 24)
    }

    @Test func pluralWords() {
        #expect(StatusChipBridgeFormat.others(1) == "+1 autre")
        #expect(StatusChipBridgeFormat.others(2) == "+2 autres")
        #expect(StatusChipBridgeFormat.cycles(0) == "0 cycle")
        #expect(StatusChipBridgeFormat.cycles(2) == "2 cycles")
    }

    // MARK: Next event

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-11-04 10:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_793_786_400)

    private func event(_ id: String, title: String = "Point", startsIn: TimeInterval, length: TimeInterval = 1800,
                       allDay: Bool = false, declined: Bool = false, joinURL: URL? = nil) -> NotchCalendarEvent {
        NotchCalendarEvent(id: id, title: title, calendar: "Travail", start: Self.now.addingTimeInterval(startsIn),
                           end: Self.now.addingTimeInterval(startsIn + length), allDay: allDay, location: "",
                           declined: declined, joinURL: joinURL)
    }

    @Test func nextEventIsTheFirstTimedUpcomingOneOfToday() throws {
        let events = [
            event("past", startsIn: -3600),
            event("running", startsIn: -600),
            event("allday", startsIn: 600, allDay: true),
            event("declined", startsIn: 900, declined: true),
            event("later", startsIn: 7200),
            event("soon", startsIn: 1200),
            event("tomorrow", startsIn: 86_400),
        ]
        let picked = try #require(NextEventChip.select(events, now: Self.now, calendar: Self.utc))
        #expect(picked.id == "soon")
        #expect(NextEventChip.select([event("tomorrow", startsIn: 86_400)], now: Self.now, calendar: Self.utc) == nil)
        #expect(NextEventChip.select([], now: Self.now, calendar: Self.utc) == nil)
    }

    @Test func nextEventPrimaryTextIsFrenchAndTruncated() {
        let short = event("a", title: "Point hebdo", startsIn: 11 * 60 + 20)
        #expect(NextEventChip.primary(for: short, now: Self.now) == "Point hebdo dans 12 min")
        let long = event("b", title: String(repeating: "x", count: 40), startsIn: 600)
        let primary = NextEventChip.primary(for: long, now: Self.now)
        #expect(primary == String(repeating: "x", count: 23) + "… dans 10 min")
        #expect(NextEventChip.primary(for: event("c", title: "  ", startsIn: 60), now: Self.now) == "Rendez-vous dans 1 min")
    }

    @Test func nextEventTextChangesAtTheMinuteRollOver() {
        // 11 min 20 s left shows "12 min"; it shows "11 min" once 11 min are left, 20 s from now.
        let wait = NextEventChip.secondsUntilTextChanges(for: event("a", startsIn: 11 * 60 + 20), now: Self.now)
        #expect(abs(wait - 20.5) < 0.001)
        #expect(NextEventChip.secondsUntilTextChanges(for: event("b", startsIn: -5), now: Self.now) == 1)
    }

    @Test func joinActionNeedsAValidatedLink() throws {
        let valid = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let withLink = NextEventChip.actions(for: event("a", startsIn: 600, joinURL: valid), openURL: { _ in }, openCalendar: {})
        #expect(withLink.map(\.title) == ["Rejoindre", "Ouvrir le calendrier"])
        let stranger = try #require(URL(string: "https://evil.example.com/meet"))
        let plain = NextEventChip.actions(for: event("b", startsIn: 600, joinURL: stranger), openURL: { _ in }, openCalendar: {})
        #expect(plain.map(\.title) == ["Ouvrir le calendrier"])
        let none = NextEventChip.actions(for: event("c", startsIn: 600), openURL: { _ in }, openCalendar: {})
        #expect(none.map(\.title) == ["Ouvrir le calendrier"])
    }

    @MainActor @Test func joinOpensOnlyTheValidatedLink() throws {
        let valid = try #require(URL(string: "https://zoom.us/j/123"))
        var opened: [URL] = []
        let actions = NextEventChip.actions(for: event("a", startsIn: 600, joinURL: valid),
                                            openURL: { opened.append($0) }, openCalendar: {})
        actions[0].handler()
        #expect(opened == [valid])
    }

    // MARK: Top app

    @Test(arguments: [(0.0, StatusChipReading.Level.normal), (59.4, .normal), (59.5, .attention), (60, .attention),
                      (89.4, .attention), (89.5, .alert), (100, .alert), (240, .alert)])
    func topAppLevel(percent: Double, level: StatusChipReading.Level) {
        #expect(TopAppChip.level(percent: percent) == level)
    }

    @Test func topAppPrimaryText() {
        #expect(TopAppChip.primary(name: "Safari", percent: 42.4) == "Safari 42 % CPU")
        #expect(TopAppChip.primary(name: "Un nom d’application très très long", percent: 7).hasSuffix("… 7 % CPU"))
        #expect(TopAppChip.primary(name: "", percent: 3) == "Appli 3 % CPU")
    }

    @Test(arguments: ["Finder", "Dock", "loginwindow", "WindowServer", "SystemUIServer", "kernel_task",
                      "ControlCenter", "Control Center", "Mac Island", "MacIsland", " finder "])
    func refusedNames(name: String) {
        #expect(TopAppQuitPolicy.isRefused(name: name, bundleID: nil, pid: 500, ownPID: 42, ownBundleID: "be.roldy.macisland"))
    }

    @Test(arguments: ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.WindowServer",
                      "com.apple.systemuiserver", "com.apple.controlcenter", "be.roldy.macisland", "BE.ROLDY.MACISLAND"])
    func refusedBundleIDs(bundleID: String) {
        #expect(TopAppQuitPolicy.isRefused(name: "Whatever", bundleID: bundleID, pid: 500, ownPID: 42, ownBundleID: nil))
    }

    @Test func refusesOwnProcessAndLowPIDsButNotOrdinaryApps() {
        #expect(TopAppQuitPolicy.isRefused(name: "Renamed", bundleID: nil, pid: 42, ownPID: 42, ownBundleID: nil))
        #expect(TopAppQuitPolicy.isRefused(name: "Renamed", bundleID: "x.y.z", pid: 500, ownPID: 42, ownBundleID: "x.y.z"))
        #expect(TopAppQuitPolicy.isRefused(name: "launchd", bundleID: nil, pid: 1, ownPID: 42, ownBundleID: nil))
        #expect(!TopAppQuitPolicy.isRefused(name: "Safari", bundleID: "com.apple.Safari", pid: 500, ownPID: 42,
                                            ownBundleID: "be.roldy.macisland"))
    }

    @MainActor @Test func topAppReadingHasNoActionWithoutQuit() {
        let reading = TopAppChip.reading(name: "Finder", percent: 95, quit: nil)
        #expect(reading.actions.isEmpty)
        #expect(reading.level == .alert)
    }

    @MainActor @Test func topAppQuitIsDestructiveAndNeedsConfirmation() throws {
        var quit = 0
        let reading = TopAppChip.reading(name: "Safari", percent: 70, quit: { quit += 1 })
        let action = try #require(reading.actions.first)
        #expect(reading.actions.count == 1)
        #expect(action.title == "Quitter")
        #expect(action.isDestructive)
        #expect(action.needsConfirmation)
        #expect(quit == 0)
    }

    // MARK: Devices

    private func device(_ id: String, _ name: String, _ percent: Int, _ kind: PeripheralBatteryKind = .audio) -> PeripheralBatteryDevice {
        PeripheralBatteryDevice(id: id, name: name, percent: percent, kind: kind)
    }

    @Test func devicesAreOrderedLowestBatteryFirst() {
        let devices = [device("1", "Souris", 55, .mouse), device("2", "AirPods Pro", 20), device("3", "Clavier", 20, .keyboard),
                       device("4", "Trackpad", 90, .trackpad)]
        let sample = PeripheralBatterySample(devices: devices, observedAt: ["1": 100, "2": 100, "3": 100, "4": 100])
        let ordered = DevicesChip.ordered(sample, now: 110)
        #expect(ordered.map(\.id) == ["2", "3", "1", "4"])
    }

    @Test func devicesDropStaleAndImplausibleSamples() {
        let devices = [device("1", "Vieux", 50), device("2", "Frais", 60), device("3", "Fou", 140), device("4", "Inconnu", 30)]
        let sample = PeripheralBatterySample(devices: devices, observedAt: ["1": 100, "2": 900, "3": 900])
        #expect(DevicesChip.ordered(sample, now: 1000).map(\.id) == ["2"])
        #expect(DevicesChip.reading([]) == nil)
    }

    @Test func devicesTextAndLevels() throws {
        let one = try #require(DevicesChip.reading([device("2", "AirPods Pro", 80)]))
        #expect(one.kind == .devices)
        #expect(one.primary == "AirPods Pro 80 %")
        #expect(one.secondary == nil)
        #expect(one.level == .normal)
        #expect(one.actions.isEmpty)
        let three = try #require(DevicesChip.reading([device("a", "AirPods", 8), device("b", "Souris", 50, .mouse),
                                                      device("c", "Clavier", 60, .keyboard)]))
        #expect(three.secondary == "+2 autres")
        #expect(three.level == .alert)
        #expect(DevicesChip.level(percent: 11) == .attention)
        #expect(DevicesChip.level(percent: 20) == .attention)
        #expect(DevicesChip.level(percent: 21) == .normal)
        #expect(DevicesChip.level(percent: 10) == .alert)
        #expect(DevicesChip.reading([device("a", "AirPods", 12), device("b", "Souris", 50, .mouse)])?.secondary == "+1 autre")
    }

    // MARK: Timer

    private func timer(mode: NotchTimerMode = .timer, phase: NotchTimerPhase = .timer, seconds: TimeInterval,
                       duration: TimeInterval, running: Bool = true, paused: Bool = false,
                       completed: Bool = false) -> TimerReading {
        TimerReading(mode: mode, phase: phase, seconds: seconds, duration: duration, isRunning: running,
                     isPaused: paused, completed: completed)
    }

    @Test func timerProgressMath() {
        #expect(timer(seconds: 300, duration: 300).progress == 0)
        #expect(timer(seconds: 75, duration: 300).progress == 0.75)
        #expect(timer(seconds: 0, duration: 300).progress == 1)
        #expect(timer(seconds: 400, duration: 300).progress == 0)
        #expect(timer(seconds: -5, duration: 300).progress == 1)
        #expect(timer(seconds: 10, duration: 0).progress == nil)
        #expect(timer(mode: .stopwatch, phase: .stopwatch, seconds: 90, duration: 0).progress == nil)
        #expect(timer(mode: .stopwatch, phase: .stopwatch, seconds: 90, duration: 300).progress == nil)
        #expect(timer(mode: .pomodoro, phase: .focus, seconds: 750, duration: 1500).progress == 0.5)
    }

    @Test func timerIndicatorKeepsUsingTheSameProgress() throws {
        let reading = timer(seconds: 75, duration: 300)
        let indicator = try #require(TimerIndicator.indicator(reading))
        #expect(indicator.progress == reading.progress)
    }

    @MainActor @Test func timerChipReadingRunning() throws {
        var toggled = 0
        let chip = try #require(TimerChip.reading(timer(seconds: 272, duration: 300), toggle: { toggled += 1 }))
        #expect(chip.kind == .timer)
        #expect(chip.primary == "4:32")
        #expect(chip.secondary == "Minuteur")
        #expect(chip.progress != nil)
        #expect(chip.actions.map(\.title) == ["Pause"])
        chip.actions[0].handler()
        #expect(toggled == 1)
    }

    @MainActor @Test func timerChipReadingPausedAndStopwatch() throws {
        let paused = try #require(TimerChip.reading(
            timer(mode: .pomodoro, phase: .focus, seconds: 600, duration: 1500, running: false, paused: true), toggle: {}))
        #expect(paused.actions.map(\.title) == ["Reprendre"])
        #expect(paused.secondary == "Pomodoro, concentration, en pause")
        let stopwatch = try #require(TimerChip.reading(
            timer(mode: .stopwatch, phase: .stopwatch, seconds: 3725, duration: 0), toggle: {}))
        #expect(stopwatch.primary == "1:02:05")
        #expect(stopwatch.progress == nil)
        #expect(stopwatch.secondary == "Chronomètre")
    }

    @MainActor @Test func timerChipIsAbsentWithoutAnActiveSession() {
        #expect(TimerChip.reading(nil, toggle: {}) == nil)
        #expect(TimerChip.reading(timer(seconds: 0, duration: 300, running: false, completed: true), toggle: {}) == nil)
        #expect(TimerChip.reading(timer(seconds: 0, duration: 300, running: false, paused: false), toggle: {}) == nil)
    }
}
