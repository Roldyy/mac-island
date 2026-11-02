import Combine
import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Harold, 2026-11-02: every island-visible ported feature, switched on, must reach the closed strip (an activity or an
/// indicator) or render its page. One test per feature: registry switch -> the lane's real start -> what the lane posts ->
/// `AmbientCenter` content (what `ClosedStrip` draws) or the ported gate its page reads. Findings: `scripts/port/ISLAND-VISIBILITY.md`.
@MainActor
@Suite(.serialized) struct IslandVisibilityTests {
    // MARK: Rigs

    /// A local activity center + ambient center, the pair the app wires with `ActivityCenter.shared` / `AmbientCenter.shared`.
    @MainActor final class Strip {
        let bench = TestDefaults.make()
        let activity = ActivityCenter()
        let ambient: AmbientCenter

        init(settings: ClosedIslandSettings = .standard, notched: Bool = true) {
            settings.write(to: bench.defaults)
            bench.defaults.set(true, forKey: ClosedIslandKeys.migrated)
            bench.defaults.set(true, forKey: ClosedIslandKeys.trimmed)  // else `load` drops a stored music choice
            ambient = AmbientCenter(activity: activity, preferences: ClosedIslandPreferences(defaults: bench.defaults),
                                    isNotched: notched, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        }

        var all: [AmbientIndicator] { ambient.content.all + [ambient.content.center].compactMap { $0 } }
        func has(channel: String) -> Bool { all.contains { $0.channel == channel } }
        func shows(text: String) -> Bool { all.contains { $0.text == text } }
        func cleanup() { bench.cleanup() }
    }

    /// A real registry over the binding's descriptors, started the way the app does.
    @MainActor struct Registry {
        let registry: FeatureRegistry
        let binding: PortFeatureBinding  // the registry's starters hold it unowned
        let ids: [String]
        let cleanup: () -> Void

        subscript(_ id: String) -> Bool {
            get { registry.switches[id] ?? false }
            nonmutating set { registry.switches[id] = newValue }
        }

        func tearDown() {
            for id in ids { registry.switches[id] = false }
            cleanup()
        }
    }

    func registry(for binding: PortFeatureBinding, strip: Strip? = nil) -> Registry {
        binding.connectAvailability()
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { id in strip?.activity.withdrawAll(source: id) })
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Registry(registry: registry, binding: binding, ids: binding.descriptors.map(\.id), cleanup: { bench.cleanup(); marker.clear() })
    }

    func binding() -> PortFeatureBinding {
        PortFeatureBinding(permissions: { PortPermissionState(accessibility: true, screenRecording: true) })
    }

    // MARK: Downloads progress

    func download(_ name: String, fraction: Double?) -> NotchDownloadItem {
        NotchDownloadItem(id: name, url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, receivedBytes: 10,
                          fraction: fraction, completed: false, active: true)
    }

    @Test func downloadsSwitchedOnShowTheirProgressInTheClosedStrip() {
        PortHostFixture.isolated { defaults in
            let strip = Strip()
            defer { strip.cleanup() }
            let subject = PassthroughSubject<[NotchDownloadItem], Never>()
            let board = IslandActivityBoard(poster: { strip.activity }, defaults: { defaults })
            let feed = IslandDownloadsFeed(items: subject.eraseToAnyPublisher(), board: board)
            let runtime = IslandDownloadsLane.Runtime(startDownloads: { feed.start() }, stopDownloads: { feed.stop() },
                                                      startWatch: {}, stopWatch: {})
            let lane = binding()
            IslandDownloadsLane.bind(into: lane, runtime: runtime)
            let reg = registry(for: lane)
            defer { reg.tearDown() }

            subject.send([download("a.zip", fraction: 0.5)])
            #expect(!strip.shows(text: "50 %"), "off: nothing")
            reg["notchDownloads"] = true
            subject.send([download("a.zip", fraction: 0.5)])
            #expect(strip.shows(text: "50 %"), "on: the ring and the percentage reach a wing")
            #expect(strip.has(channel: AmbientChannel.alert))
            reg["notchDownloads"] = false
            #expect(!strip.shows(text: "50 %"), "off again: withdrawn")
        }
    }

    // MARK: Watch

    @Test func aWatchSwitchedOnShowsItsReadingAndItsEnd() {
        PortHostFixture.isolated { defaults in
            let strip = Strip()
            defer { strip.cleanup() }
            let subject = PassthroughSubject<(NotchWatchState, String), Never>()
            let board = IslandActivityBoard(poster: { strip.activity }, defaults: { defaults })
            let feed = IslandWatchFeed(state: subject.eraseToAnyPublisher(), board: board, title: { _ in "Fini" })
            let runtime = IslandDownloadsLane.Runtime(startDownloads: {}, stopDownloads: {},
                                                      startWatch: { feed.start() }, stopWatch: { feed.stop() })
            let lane = binding()
            IslandDownloadsLane.bind(into: lane, runtime: runtime)
            let reg = registry(for: lane, strip: strip)
            defer { reg.tearDown() }

            reg["notchWatch"] = true
            subject.send((.watching, "42 %"))
            #expect(strip.shows(text: "42 %"))
            subject.send((.finished(.changed), ""))
            #expect(strip.shows(text: "Fini"), "the outcome outranks and is shown")
            reg["notchWatch"] = false
            #expect(!strip.shows(text: "Fini"))
        }
    }

    // MARK: Timer, Pomodoro, stopwatch, alarm

    func timerRuntime(strip: Strip, defaults: UserDefaults, reading: TimerReading?,
                      calendar: AmbientIndicator? = nil) -> TimerRuntime {
        let long: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }
        let timer = ClosedIslandTicker(id: TimerIndicator.id, hooks: .init(
            isOn: { TimerIndicator.isOn(in: defaults) }, make: { _ in TimerIndicator.indicator(reading) },
            post: { strip.ambient.post($0) }, withdraw: { strip.ambient.withdraw(id: $0) }, sleep: long))
        let agenda = ClosedIslandTicker(id: CalendarIndicator.id, hooks: .init(
            isOn: { CalendarIndicator.isOn(in: defaults) }, make: { _ in calendar },
            post: { strip.ambient.post($0) }, withdraw: { strip.ambient.withdraw(id: $0) }, sleep: long))
        return TimerRuntime(
            syncTimer: {}, stopTimer: {}, syncCalendar: {}, stopCalendar: {}, syncNotifications: {}, stopNotifications: {},
            syncAccessories: {}, stopAccessories: {}, watchTimer: { _ in nil }, watchCalendar: { _ in nil },
            timerTicker: { timer }, calendarTicker: { agenda })
    }

    func running(_ phase: NotchTimerPhase = .timer, mode: NotchTimerMode = .timer, seconds: TimeInterval = 75) -> TimerReading {
        TimerReading(mode: mode, phase: phase, seconds: seconds, duration: 300, isRunning: true, isPaused: false)
    }

    @Test func aRunningTimerPomodoroOrStopwatchShowsItsClockOnceTheFeatureIsOn() {
        PortHostFixture.isolated { defaults in
            PortIslandHosting.reset()
            defer { PortIslandHosting.reset() }
            for (phase, mode, text) in [(NotchTimerPhase.timer, NotchTimerMode.timer, "1:15"),
                                        (.focus, .pomodoro, "1:15"), (.stopwatch, .stopwatch, "1:15")] {
                let strip = Strip()
                defer { strip.cleanup() }
                let lane = binding()
                TimerLane.bind(into: lane, runtime: timerRuntime(
                    strip: strip, defaults: defaults, reading: running(phase, mode: mode)))
                let reg = registry(for: lane)
                defer { reg.tearDown() }
                #expect(!strip.has(channel: TimerIndicator.id), "off: nothing")
                reg["notchTimer"] = true
                #expect(strip.shows(text: text) && strip.has(channel: TimerIndicator.id), "\(phase)")
                reg["notchTimer"] = false
                #expect(!strip.has(channel: TimerIndicator.id))
            }
        }
    }

    @Test func theTimersClosedIslandSwitchIsOnByDefaultAndTheTabCanTurnItOff() {
        PortHostFixture.isolated { defaults in
            #expect(TimerIndicator.isOn(in: defaults))
            defaults.set(false, forKey: TimerIndicator.switchKey)
            #expect(!TimerIndicator.isOn(in: defaults))
            PortIslandHosting.reset()
            defer { PortIslandHosting.reset() }
            let strip = Strip()
            defer { strip.cleanup() }
            let lane = binding()
            TimerLane.bind(into: lane, runtime: timerRuntime(strip: strip, defaults: defaults, reading: running()))
            let reg = registry(for: lane)
            defer { reg.tearDown() }
            reg["notchTimer"] = true
            #expect(!strip.has(channel: TimerIndicator.id), "the person's own off wins")
        }
    }

    // MARK: Calendar

    @Test func theNextAppointmentShowsOnlyWhenItsClosedIslandSwitchIsOn() {
        PortHostFixture.isolated { defaults in
            PortIslandHosting.reset()
            defer { PortIslandHosting.reset() }
            let now = Date()
            let next = CalendarIndicator.indicator(title: "Revue", target: now.addingTimeInterval(20 * 60), ongoing: false, now: now)
            #expect(next != nil)
            for on in [false, true] {
                defaults.set(on, forKey: CalendarIndicator.switchKey)
                let strip = Strip()
                defer { strip.cleanup() }
                let lane = binding()
                TimerLane.bind(into: lane, runtime: timerRuntime(strip: strip, defaults: defaults, reading: nil, calendar: next))
                let reg = registry(for: lane)
                defer { reg.tearDown() }
                reg["notchCalendar"] = true
                #expect(strip.has(channel: CalendarIndicator.id) == on, "switch \(on)")
            }
        }
    }

    // MARK: Notifications, accessories, the finished-timer alarm

    @Test func noticesOfTheHostedFeaturesReachTheStripOnlyWhileTheirSwitchIsOn() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            PortIslandHosting.reset()
            defer { PortIslandHosting.reset() }
            let strip = Strip()
            defer { strip.cleanup() }
            let lane = binding()
            TimerLane.bind(into: lane, runtime: timerRuntime(strip: strip, defaults: defaults, reading: nil))
            let reg = registry(for: lane, strip: strip)
            defer { reg.tearDown() }
            let output = PortIslandOutput()
            output.post = { strip.activity.post($0, expiresAfter: $1) }
            let accessory = NotchNotice(event: .accessory, title: "AirPods", detail: "Batterie faible", symbol: "airpodspro", level: 0.18)
            let mirrored = NotchNotice(event: .systemNotification, title: "Mail", detail: "Nouveau message", symbol: "bell")
            let alarm = NotchNotice(event: .timer, title: "Terminé", detail: "", symbol: "timer")

            // A notice is a glyph and a short text; a notched wing is narrow, so a long text may be cut to its glyph
            // (`AmbientMetrics.fitted`): the alert indicator with the notice's own symbol is what must reach the strip.
            for (id, notice, symbol) in [("notchAccessories", accessory, "airpodspro"), ("notchNotifications", mirrored, "bell"),
                                         ("notchTimer", alarm, "timer")] {
                output.isRouted = PortIslandOutput.liveRouting
                #expect(output.present(notice) == false, "\(id) off: refused")
                reg[id] = true
                #expect(output.present(notice), "\(id) on: taken")
                #expect(strip.all.contains { $0.channel == AmbientChannel.alert && $0.symbol == symbol },
                        "\(id): its alert reaches a wing")
                reg[id] = false
                #expect(!strip.all.contains { $0.channel == AmbientChannel.alert }, "\(id) off: withdrawn with its feature")
            }
        }
    }

    // MARK: Music: wing, lyrics, queue, equalizer

    func musicRuntime(strip: Strip, playing: Box<(@MainActor (MusicNowPlaying?) -> Void)?>) -> MusicRuntime {
        MusicRuntime(
            capability: { .available(script: "now-playing.pl", library: "libMacIslandNowPlaying.dylib") },
            startPlayback: {}, stopPlayback: {}, syncQueue: {}, syncLyrics: {}, stopLyrics: {}, syncEqualizer: {},
            stopEqualizer: {},
            watchPlayback: { onChange in playing.value = onChange; return nil },
            post: { strip.activity.post($0) }, withdraw: { strip.activity.withdraw(id: $0) })
    }

    @Test func theMusicWingShowsATrackWhenItsIndicatorIsSwitchedOnAndNotBefore() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            PortIslandHosting.reset()
            defer { PortIslandHosting.reset() }
            for musicOn in [false, true] {
                var settings = ClosedIslandSettings.standard
                if musicOn { settings.enabled.insert(AmbientChannel.music) }
                let strip = Strip(settings: settings)
                defer { strip.cleanup() }
                let playing = Box<(@MainActor (MusicNowPlaying?) -> Void)?>(nil)
                let session = MusicSession(runtime: musicRuntime(strip: strip, playing: playing))
                let lane = binding()
                MusicLane.bind(into: lane, session: session)
                let reg = registry(for: lane)
                defer { reg.tearDown() }
                reg["notchLyrics"] = true
                playing.value?(MusicNowPlaying(title: "Hollow Years", isPlaying: true, progress: 0.4))
                #expect(strip.has(channel: AmbientChannel.music) == musicOn,
                        "the music wing is a Settings choice, off by default (closed island rule)")
                if musicOn { #expect(strip.all.first { $0.channel == AmbientChannel.music }?.glyph == .equalizer) }
                playing.value?(nil)
                #expect(!strip.has(channel: AmbientChannel.music), "playback ended: wing withdrawn")
            }
        }
    }

    @Test func lyricsQueueAndTheLiveEqualizerAreLiveOnceTheirSwitchIsOn() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            PortIslandHosting.reset()
            defer { PortIslandHosting.reset() }
            let strip = Strip()
            defer { strip.cleanup() }
            let session = MusicSession(runtime: musicRuntime(strip: strip, playing: Box(nil)))
            let lane = binding()
            MusicLane.bind(into: lane, session: session)
            let reg = registry(for: lane)
            defer { reg.tearDown() }

            #expect(!NotchLyricsSupport.isEnabled(in: defaults) && !NotchQueueSupport.isEnabled(in: defaults))
            #expect(!NotchAudioLevelSupport.isEnabled(in: defaults))
            reg["notchLyrics"] = true
            reg["notchQueue"] = true
            reg["notchLiveEqualizer"] = true
            #expect(NotchLyricsSupport.isEnabled(in: defaults), "lyrics page")
            #expect(NotchQueueSupport.isEnabled(in: defaults), "queue page")
            #expect(NotchAudioLevelSupport.isEnabled(in: defaults), "the equalizer's own upstream key must follow the switch")
        }
    }

    // MARK: Lock screen island

    @Test func theLockScreenIslandSwitchedOnTurnsItsOwnUpstreamKeyOnOnceAndTheSceneSyncs() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            let service = IslandLockScreenTests.FakeService()
            let controller = IslandLockScreenController(service: service, capability: { .available }, playsSounds: { false })
            let runtime = IslandLockScreenLane.Runtime(
                startLock: {
                    IslandActivityHost.shared.acquire(IslandLockScreenLane.lockScreenID)
                    var locked = NotchSessionState()
                    locked.locked = true
                    controller.start(initial: locked, observe: false)
                },
                stopLock: { controller.stop(); IslandActivityHost.shared.release(IslandLockScreenLane.lockScreenID) },
                startGestures: {}, stopGestures: {}, startMascot: {}, stopMascot: {})
            let lane = binding()
            IslandLockScreenLane.bind(into: lane, runtime: runtime)
            let reg = registry(for: lane)
            defer { reg.tearDown() }

            #expect(!NotchLockScreenSupport.isEnabled(in: defaults))
            reg["lockscreen"] = true
            #expect(NotchLockScreenSupport.isEnabled(in: defaults), "the Fonctions switch is the opt-in")
            #expect(service.events.contains("sync:locked"), "the scene is handed the locked session")
            #expect(!NotchLockScreenSupport.playsSounds(in: defaults), "the padlock sounds stay the person's own tick")
            // A person who ticked the scene off keeps it off across a restart of the feature.
            defaults.set(false, forKey: DefaultsKey.notchLockScreen)
            reg["lockscreen"] = false
            reg["lockscreen"] = true
            #expect(!NotchLockScreenSupport.isEnabled(in: defaults))
        }
    }

    // MARK: Mirror

    @Test func theMirrorPageRendersOnlyWithItsSwitchAndItsHost() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            func canPresent() -> Bool {
                NotchCameraSupport.canPresent(expanded: false, selected: .controls, appPanel: false, captureControls: false,
                                              in: defaults)
            }
            PortHost.availability = { $0 == "cameraPreview" ? true : nil }
            #expect(!canPresent(), "the tab has not opened: the camera stays dark")
            IslandActivityHost.shared.acquire(IslandMirrorTab.owner)
            defer { IslandActivityHost.shared.release(IslandMirrorTab.owner) }
            #expect(canPresent(), "the Miroir tab on screen with the camera feature on")
            PortHost.availability = { _ in false }
            #expect(!canPresent(), "feature off: the page shows its off notice, not the camera")
            #expect(ShellTabGate.ported.isEnabled("mirror", enabled: { $0 == "cameraPreview" }))
        }
    }

    // MARK: Every island tab has its switch

    @Test func everyIslandPageOpensWithItsFeatureSwitch() {
        let gate = ShellTabGate.ported
        for (tab, ids) in gate.features {
            for id in ids { #expect(gate.isEnabled(tab, enabled: { $0 == id }), "\(tab) opens with \(id)") }
            #expect(!gate.isEnabled(tab, enabled: { _ in false }))
        }
    }
}
