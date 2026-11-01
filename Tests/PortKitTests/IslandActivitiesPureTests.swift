import Foundation
import IslandKit
import IslandUI
import Testing
@testable import PortKit

/// Lanes W8A and W8B, the parts that are pure: indicators, notice mapping, the adapter probe, the closed island rule
/// and the source gates. No registry, no service, no host state.
@MainActor
struct IslandActivitiesPureTests {
    // MARK: Timer and calendar indicators

    func reading(_ phase: NotchTimerPhase = .timer, mode: NotchTimerMode = .timer, seconds: TimeInterval = 65,
                 duration: TimeInterval = 300, running: Bool = true, paused: Bool = false,
                 completed: Bool = false) -> TimerReading {
        TimerReading(mode: mode, phase: phase, seconds: seconds, duration: duration, isRunning: running, isPaused: paused,
                     completed: completed)
    }

    @Test func theClockReadsMinutesAndHours() {
        #expect(TimerIndicator.clockText(65) == "1:05")
        #expect(TimerIndicator.clockText(0) == "0:00")
        #expect(TimerIndicator.clockText(3725) == "1:02:05")
        #expect(TimerIndicator.clockText(-4) == "0:00")
    }

    @Test func aRunningCountdownIsAReadableIndicatorWithItsClockAndRing() throws {
        let indicator = try #require(TimerIndicator.indicator(reading(seconds: 75, duration: 300)))
        #expect(indicator.id == "timer" && indicator.text == "1:15" && indicator.symbol == "timer")
        #expect(indicator.progress == 0.75)
        #expect(indicator.isReadable, "a clock is a value: never an icon alone")
        #expect(indicator.label == "Minuteur : 1:15")
        #expect(indicator.accessibilityLabel().contains("1:15"))
    }

    @Test func aStopwatchHasNoRingAndAPausedTimerSaysSo() throws {
        let stopwatch = try #require(TimerIndicator.indicator(reading(.stopwatch, mode: .stopwatch, seconds: 12, duration: 0)))
        #expect(stopwatch.progress == nil && stopwatch.symbol == "stopwatch" && stopwatch.text == "0:12")
        let paused = try #require(TimerIndicator.indicator(reading(running: false, paused: true)))
        #expect(paused.symbol == "pause.fill" && paused.status == .warning)
        #expect(paused.label?.hasSuffix("en pause") == true)
    }

    @Test func eachPomodoroPhaseHasItsWordAndAFinishedSessionShowsNothing() throws {
        #expect(TimerIndicator.phaseWord(reading(.focus, mode: .pomodoro)) == "Pomodoro, concentration")
        #expect(TimerIndicator.phaseWord(reading(.shortBreak, mode: .pomodoro)) == "Pomodoro, courte pause")
        #expect(TimerIndicator.phaseWord(reading(.longBreak, mode: .pomodoro)) == "Pomodoro, longue pause")
        #expect(TimerIndicator.indicator(reading(completed: true)) == nil, "the end is an alert, not a clock")
        #expect(TimerIndicator.indicator(nil) == nil)
    }

    @Test func theCalendarCountdownNeedsTextAndAFutureMoment() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let soon = try #require(CalendarIndicator.indicator(title: "Revue", target: now.addingTimeInterval(605), ongoing: false, now: now))
        #expect(soon.text == "10:05" && soon.channel == "calendar" && soon.isReadable)
        #expect(soon.label == "Début de Revue dans 10:05")
        let ending = try #require(CalendarIndicator.indicator(title: "", target: now.addingTimeInterval(60), ongoing: true, now: now))
        #expect(ending.label == "Fin de l’événement dans 1:00")
        #expect(CalendarIndicator.indicator(title: "Passé", target: now.addingTimeInterval(-1), ongoing: false, now: now) == nil)
    }

    // MARK: The ticker

    @MainActor final class Spy {
        var posted: [AmbientIndicator] = []
        var withdrawn: [String] = []
        var on = true
        var sleeps = 0
    }

    @MainActor @Test func theTickerPostsWhileOnTicksOnceASecondAndWithdrawsWhenSwitchedOff() async {
        let spy = Spy()
        let indicator = AmbientIndicator(id: "timer", channel: "timer", symbol: "timer", text: "1:00")
        let ticker = ClosedIslandTicker(id: "timer", hooks: .init(
            isOn: { spy.on }, make: { _ in indicator }, post: { spy.posted.append($0) },
            withdraw: { spy.withdrawn.append($0) },
            sleep: { _ in
                // Two instant seconds, then wait for the cancel.
                let n = await MainActor.run { spy.sleeps += 1; return spy.sleeps }
                if n > 2 { try await Task.sleep(for: .seconds(3600)) }
            }))
        ticker.refresh()
        #expect(ticker.isTicking)
        for _ in 0..<200 where spy.sleeps < 3 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(spy.posted.count >= 3, "one post now, one per second")
        spy.on = false
        ticker.refresh()
        #expect(spy.withdrawn.last == "timer" && ticker.isTicking == false, "off by the user's switch: nothing is shown or timed")
        ticker.stop()
    }

    @MainActor @Test func aTickerWithNothingToShowPostsNothingAndDoesNotTick() {
        var posted = 0
        var withdrawn: [String] = []
        let ticker = ClosedIslandTicker(id: "calendar", hooks: .init(
            isOn: { true }, make: { _ in nil }, post: { _ in posted += 1 }, withdraw: { withdrawn.append($0) }))
        ticker.refresh()
        #expect(posted == 0 && withdrawn == ["calendar"] && ticker.isTicking == false)
    }

    // MARK: Notices of the old island

    func notice(_ event: NotchEvent, title: String = "", detail: String = "", symbol: String = "bell",
                level: Double? = nil, notification: NotchNotificationContent? = nil) -> NotchNotice {
        NotchNotice(event: event, title: title, detail: detail, symbol: symbol, level: level, notification: notification)
    }

    @Test func aTimerEndBecomesAShortAlertWithItsWord() throws {
        let mapped = try #require(IslandNoticeMapper.activity(for: notice(.timer, title: "Terminé", detail: "Minuteur", symbol: "timer")))
        #expect(mapped.activity.priority == .alert && mapped.activity.source == "notchTimer")
        #expect(mapped.activity.leading?.text == "Terminé" && mapped.activity.leading?.symbol == "timer")
        #expect(mapped.lifetime == .seconds(6))
    }

    @Test func aLowAccessoryShowsItsNameAndPercentAndAConnectionItsDevice() throws {
        let low = try #require(IslandNoticeMapper.activity(
            for: notice(.accessory, title: "Magic Mouse", detail: "Batterie faible · 8%", symbol: "computermouse", level: 0.08)))
        #expect(low.activity.leading?.text == "Magic Mouse 8 %" && low.activity.leading?.status == .danger)
        #expect(low.activity.source == "notchAccessories" && low.lifetime == .seconds(4))
        let connected = try #require(IslandNoticeMapper.activity(
            for: notice(.accessory, title: "Connecté", detail: "AirPods Pro", symbol: "airpodspro")))
        #expect(connected.activity.leading?.text == "AirPods Pro" && connected.activity.leading?.status == .info)
    }

    @Test func aMirroredNotificationShowsItsTitleOrItsAppAndLongTextIsCut() throws {
        let content = NotchNotificationContent(app: "Messages", title: "", subtitle: "", body: "Salut")
        let mapped = try #require(IslandNoticeMapper.activity(for: notice(.systemNotification, notification: content)))
        #expect(mapped.activity.leading?.text == "Messages" && mapped.activity.source == "notchNotifications")
        let long = String(repeating: "a", count: 60)
        let cut = try #require(IslandNoticeMapper.activity(for: notice(.timer, title: long)))
        #expect((cut.activity.leading?.text ?? "").count == IslandNoticeMapper.maximumLength)
        #expect(cut.activity.leading?.text?.hasSuffix("…") == true)
    }

    @Test func noticesOfOtherLanesAndEmptyOnesAreRefused() {
        for event in [NotchEvent.volume, .brightness, .battery, .clipboard, .capture, .keyboardLight, .download, .agents,
                      .track, .microphone, .watch, .inputSource] {
            #expect(IslandNoticeMapper.activity(for: notice(event, title: "x")) == nil, "\(event)")
        }
        #expect(IslandNoticeMapper.activity(for: notice(.timer)) == nil, "no text: no alert (never an icon alone)")
    }

    @Test func everyMappedNoticeReachesTheClosedIslandAsAReadableAlert() throws {
        let content = NotchNotificationContent(app: "Mail", title: "Facture", subtitle: "", body: "")
        for item in [notice(.timer, title: "Terminé"),
                     notice(.accessory, title: "Clavier", level: 0.15),
                     notice(.accessory, title: "Connecté", detail: "Trackpad"),
                     notice(.systemNotification, notification: content)] {
            let mapped = try #require(IslandNoticeMapper.activity(for: item))
            let layout = ActivityArbiter.resolve([mapped.activity])
            let indicators = AmbientBridge.indicators(from: layout, claude: nil)
            #expect(indicators.count == 1 && indicators[0].channel == AmbientChannel.alert)
            #expect(indicators[0].text?.isEmpty == false, "no icon-only item")
            #expect(indicators[0].isReadable)
        }
    }

    // MARK: Music wing

    @Test func theMusicWingNeedsAPlayingTrackWithATitle() throws {
        #expect(MusicActivity.activity(for: nil) == nil)
        #expect(MusicActivity.activity(for: MusicNowPlaying(title: "A", isPlaying: false, progress: nil)) == nil)
        #expect(MusicActivity.activity(for: MusicNowPlaying(title: "", isPlaying: true, progress: nil)) == nil, "no title, no icon-only wing")
        let activity = try #require(MusicActivity.activity(for: MusicNowPlaying(
            title: "Une chanson au titre vraiment trop long", isPlaying: true, progress: 0.4)))
        #expect(activity.trailing?.text?.count == MusicActivity.maximumTitle && activity.trailing?.text?.hasSuffix("…") == true)
        #expect(activity.leading?.progress == 0.4 && activity.priority == .music && activity.id == "music.port")
        let indicators = AmbientBridge.indicators(from: ActivityArbiter.resolve([activity]), claude: nil)
        #expect(indicators.count == 1 && indicators[0].channel == AmbientChannel.music && indicators[0].glyph == .equalizer,
                "the existing bridge recognises it as the music indicator, a Settings switch off by default")
    }

    // MARK: Adapter probe

    func locator(killed: Bool = false, files: Set<String> = ["/usr/bin/perl", "/app/now-playing.pl", "/app/lib.dylib"],
                 script: String? = "/app/now-playing.pl", library: String? = "/app/lib.dylib") -> MediaRemoteAdapterLocator {
        MediaRemoteAdapterLocator(isKilled: { killed }, fileExists: { files.contains($0) },
                                  scriptPath: { script }, libraryPath: { library })
    }

    @Test func theProbeFindsTheAdapterOrNamesTheMissingPiece() {
        #expect(locator().capability() == .available(script: "/app/now-playing.pl", library: "/app/lib.dylib"))
        #expect(locator().launchArguments() == ["/app/now-playing.pl", "/app/lib.dylib"])
        #expect(locator(killed: true).capability() == .unavailable(.killSwitch))
        #expect(locator(files: ["/app/now-playing.pl", "/app/lib.dylib"]).capability() == .unavailable(.perlMissing))
        #expect(locator(files: ["/usr/bin/perl", "/app/lib.dylib"]).capability() == .unavailable(.scriptMissing))
        #expect(locator(script: nil).capability() == .unavailable(.scriptMissing), "not bundled (swift run)")
        #expect(locator(files: ["/usr/bin/perl", "/app/now-playing.pl"]).capability() == .unavailable(.libraryMissing))
        #expect(locator(library: nil).capability() == .unavailable(.libraryMissing))
    }

    @Test func theKillSwitchBeatsEverythingAndAnUnavailableAdapterLaunchesNothing() {
        #expect(locator(killed: true).launchArguments() == nil)
        #expect(locator(files: []).launchArguments() == nil)
        for reason in [MediaRemoteUnavailableReason.killSwitch, .perlMissing, .scriptMissing, .libraryMissing] {
            #expect(reason.message.hasSuffix(".") && reason.message.count > 40, "\(reason): a sentence for the page")
        }
    }

    @Test func theLiveProbeReadsTheHostsKillSwitch() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: MediaRemoteAdapterLocator.killSwitchKey)
            #expect(MediaRemoteAdapterLocator.live.capability() == .unavailable(.killSwitch))
            defaults.set(false, forKey: MediaRemoteAdapterLocator.killSwitchKey)
            // `swift test` has no bundle with the adapter: unavailable, a reason and no launch.
            #expect(MediaRemoteAdapterLocator.live.launchArguments() == nil)
        }
    }

    // MARK: The closed island rule

    @Test func theClosedIslandDefaultsAreStillClaudeClockBatteryAndTheCupAndNothingElse() {
        #expect(AmbientChannel.defaultOn == [AmbientChannel.limits, AmbientChannel.claude, AmbientChannel.battery,
                                             AmbientChannel.keepAwake, AmbientChannel.clock])
        #expect(AmbientChannel.defaultOn.contains(AmbientChannel.music) == false)
        #expect(ClosedIslandSettings.standard.isEnabled(AmbientChannel.music) == false)
    }

    @MainActor @Test func theTimerAndCalendarIndicatorsAreOffUntilTheUserSwitchesThemOn() {
        PortHostFixture.isolated { defaults in
            Defaults.register(in: defaults)
            #expect(defaults.bool(forKey: TimerIndicator.switchKey) == false)
            #expect(defaults.bool(forKey: CalendarIndicator.switchKey) == false)
            #expect(TimerIndicator.switchKey == ClosedIslandKeys.show("timer"), "the key a future `timer` channel would use")
            #expect(CalendarIndicator.switchKey == ClosedIslandKeys.show("calendar"))
        }
    }

    // MARK: Accessories tab

    @Test func theAccessoryListShowsTheLowestBatteryFirstAndFlagsLowOnes() {
        let devices = [
            PeripheralBatteryDevice(id: "a", name: "Magic Keyboard", percent: 80, kind: .keyboard),
            PeripheralBatteryDevice(id: "b", name: "Magic Mouse", percent: 12, kind: .mouse),
            PeripheralBatteryDevice(id: "c", name: "AirPods", percent: 130, kind: .audio),
        ]
        let rows = AccessoryRowModel.rows(from: devices)
        #expect(rows.map(\.name) == ["Magic Mouse", "Magic Keyboard", "AirPods"])
        #expect(rows[0].isLow && !rows[1].isLow)
        #expect(rows[2].percent == 100, "clamped")
        #expect(rows[0].spoken == "Magic Mouse, 12 pour cent, batterie faible")
        #expect(rows[0].symbol == "computermouse")
    }

    // MARK: Source gates

    static var root: URL { PortSourceScrubTests.repoRoot }

    func text(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theLanesAreInTheListAndTheAdapterIsItsOwnLibraryTarget() throws {
        let lanes = try text("Sources/PortKit/Bridge/PortLanes.swift")
        #expect(lanes.contains("MusicLane.bind(into:)") && lanes.contains("TimerLane.bind(into:)"))
        let package = try text("Package.swift")
        #expect(package.contains("type: .dynamic, targets: [\"NowPlayingAdapter\"]"))
        #expect(package.contains(".target(name: \"NowPlayingAdapter\""))
        let portKit = package.components(separatedBy: ".target(name: \"PortKit\"").last ?? ""
        #expect(!(portKit.components(separatedBy: "\n").first ?? "").contains("NowPlayingAdapter"),
                "PortKit never links the private-symbol library")
    }

    @Test func onlyPrivateFilesOfTheAdapterTouchMediaRemote() throws {
        let adapter = Self.root.appendingPathComponent("Sources/NowPlayingAdapter")
        let files = try FileManager.default.contentsOfDirectory(atPath: adapter.path).filter { $0.hasSuffix(".swift") }
        let withSymbols = try files.filter {
            try String(contentsOf: adapter.appendingPathComponent($0), encoding: .utf8).contains("MediaRemote")
        }
        #expect(!withSymbols.isEmpty && withSymbols.allSatisfy { $0.hasPrefix("Private") },
                "private symbols live in Private*.swift: \(withSymbols)")
        for name in ["IslandMusic", "IslandTimer", "IslandOutput", "PrivateMediaRemoteAdapter"] {
            let source = try text("Sources/PortKit/Bridge/\(name).swift")
            #expect(!source.contains("dlopen") && !source.contains("dlsym") && !source.contains("@_silgen_name"), "\(name)")
        }
        let music = try text("Sources/PortKit/Services/Notch/NotchMusicService.swift")
        #expect(music.contains("MediaRemoteAdapterLocator.live.launchArguments()"), "the probe and kill switch sit in front of the launch")
    }

    @Test func noLaneFileAsksForAPermissionDirectly() throws {
        for name in ["IslandMusic", "IslandTimer", "IslandOutput", "PrivateMediaRemoteAdapter"] {
            let source = try text("Sources/PortKit/Bridge/\(name).swift")
            for forbidden in ["requestFullAccess", "requestAccess(", "requestCalendar(", "CGRequestScreenCapture",
                              "AXIsProcessTrustedWithOptions", "kAXTrustedCheckOptionPrompt", "UNUserNotificationCenter"] {
                #expect(!source.contains(forbidden), "\(name): \(forbidden)")
            }
        }
    }

    @Test func theFivePatchesApplyAsNumberedAndStayInTheLaneRange() throws {
        let dir = Self.root.appendingPathComponent("scripts/port/patches")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("16") }.sorted()
        #expect(names == ["1600-hosted-island-features-gate.patch", "1601-equalizer-taps-need-click-grant.patch",
                          "1602-notice-goes-to-our-island.patch", "1603-music-adapter-capability-probe.patch",
                          "1604-lyrics-import-uses-key-window.patch"])
    }

    @Test func theEqualizerNeverCreatesATapBeforeTheClickThatProvedTheGrant() throws {
        let service = try text("Sources/PortKit/Services/Notch/NotchAudioLevelService.swift")
        #expect(service.contains("MixerAudioCapture.allowsTaps"))
        #expect(MixerAudioCapture.state(evidence: nil, hasUsageDescription: true).allowsTaps == false)
        #expect(MixerAudioCapture.state(evidence: 0, hasUsageDescription: true).allowsTaps)
    }
}
