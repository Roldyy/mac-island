import Combine
import Foundation
import IslandKit
import IslandTestSupport
import IslandUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lanes W8A (music) and W8B (timer, calendar, accessories, notifications): bound through fake runtimes and a real
/// `FeatureRegistry`. Nothing here starts an adapter process, a timer, EventKit, a notification reader or a tap, and
/// nothing prompts. One serialized suite: the hosting flag and the notice sink are process-wide.
@MainActor
@Suite(.serialized) struct IslandActivitiesLaneTests {
    // MARK: Fakes

    final class MusicFake {
        var events: [String] = []
        var capability: MediaRemoteCapability = .available(script: "/fake/now-playing.pl", library: "/fake/lib.dylib")
        var onChange: (@MainActor (MusicNowPlaying?) -> Void)?
        var posted: [IslandActivity] = []
        var withdrawn: [String] = []

        func runtime() -> MusicRuntime {
            MusicRuntime(
                capability: { self.capability },
                startPlayback: { self.events.append("start") },
                stopPlayback: { self.events.append("stop") },
                syncQueue: { self.events.append("queue") },
                syncLyrics: { self.events.append("lyrics") },
                stopLyrics: { self.events.append("lyrics.stop") },
                syncEqualizer: { self.events.append("eq") },
                stopEqualizer: { self.events.append("eq.stop") },
                watchPlayback: { onChange in
                    self.onChange = onChange
                    self.events.append("watch")
                    return AnyCancellable { self.events.append("unwatch") }
                },
                post: { self.posted.append($0) },
                withdraw: { self.withdrawn.append($0) })
        }

        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    @MainActor final class TimerFake {
        var events: [String] = []
        var timerPosted: [AmbientIndicator] = []
        var refreshes = 0

        func runtime() -> TimerRuntime {
            let ticker = ClosedIslandTicker(id: "timer", hooks: .init(
                isOn: { false }, make: { _ in nil }, post: { self.timerPosted.append($0) },
                withdraw: { self.events.append("withdraw.\($0)") }))
            return TimerRuntime(
                syncTimer: { self.events.append("timer") }, stopTimer: { self.events.append("timer.stop") },
                syncCalendar: { self.events.append("calendar") }, stopCalendar: { self.events.append("calendar.stop") },
                syncNotifications: { self.events.append("notifications") },
                stopNotifications: { self.events.append("notifications.stop") },
                syncAccessories: { self.events.append("accessories") },
                stopAccessories: { self.events.append("accessories.stop") },
                watchTimer: { _ in self.events.append("watch.timer"); return AnyCancellable {} },
                watchCalendar: { _ in self.events.append("watch.calendar"); return AnyCancellable {} },
                timerTicker: { ticker }, calendarTicker: { ticker })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let cleanup: () -> Void
    }

    func rig(accessibility: Box<Bool> = Box(true), bind: (PortFeatureBinding) -> Void) -> Rig {
        PortIslandHosting.reset()
        let binding = PortFeatureBinding(permissions: { PortPermissionState(accessibility: accessibility.value) })
        bind(binding)
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { accessibility.value }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, cleanup: { bench.cleanup(); marker.clear(); PortIslandHosting.reset() })
    }

    func musicRig(_ fake: MusicFake) -> (Rig, MusicSession) {
        let session = MusicSession(runtime: fake.runtime())
        return (rig { MusicLane.bind(into: $0, session: session) }, session)
    }

    // MARK: Music

    @Test func theThreeMusicFeaturesAreNewDescriptorsAndAllOffUntilChosen() {
        let fake = MusicFake()
        let (r, _) = musicRig(fake)
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["notchLyrics", "notchQueue", "notchLiveEqualizer"])
        for descriptor in r.binding.descriptors {
            #expect(descriptor.enabledByDefault == false, "\(descriptor.id): closed island rule, nothing on by default")
            #expect(descriptor.category == .island && !descriptor.title.isEmpty && !descriptor.summary.isEmpty)
            #expect(r.registry.state(for: descriptor.id) == .off)
        }
        let equalizer = r.registry.descriptor("notchLiveEqualizer")
        #expect(equalizer?.permissions.contains(.audioCapture) == true)
        #expect(fake.events.isEmpty, "binding starts nothing")
        #expect(PortHost.hostsIslandFeatures == false)
    }

    @Test func theAdapterStartsWithTheFirstFeatureOnceAndStopsWithTheLast() {
        let fake = MusicFake()
        let (r, session) = musicRig(fake)
        defer { r.cleanup() }
        r.registry.switches["notchLyrics"] = true
        #expect(fake.events == ["start", "watch", "lyrics"])
        #expect(PortHost.hostsIslandFeatures, "the ported lyrics gate opens only while a lane hosts it")
        r.registry.switches["notchQueue"] = true
        #expect(fake.count("start") == 1, "one adapter process for all the music features")
        #expect(fake.events.suffix(1) == ["queue"])
        r.registry.switches["notchLyrics"] = false
        #expect(fake.count("stop") == 0 && fake.count("lyrics.stop") == 1, "the queue still needs the adapter")
        r.registry.switches["notchQueue"] = false
        #expect(fake.count("stop") == 1 && fake.count("unwatch") == 1)
        #expect(fake.withdrawn.contains(MusicActivity.id), "the music wing goes with the last feature")
        #expect(PortHost.hostsIslandFeatures == false && session.isPlaybackRunning == false)
    }

    @Test func anUnavailableAdapterIsAnAnswerNeverACrashAndNothingIsLaunched() {
        let fake = MusicFake()
        fake.capability = .unavailable(.libraryMissing)
        let (r, session) = musicRig(fake)
        defer { r.cleanup() }
        r.registry.switches["notchLyrics"] = true
        #expect(fake.count("start") == 0 && fake.count("watch") == 0)
        #expect(session.isPlaybackRunning == false)
        #expect(session.capability.unavailableReason?.message.contains("Mac Island") == true,
                "the page says why, in French")
    }

    @Test func theTabHoldsTheSessionWhileItIsOnScreenAndNoLongerThanTheFeatures() {
        let fake = MusicFake()
        let (r, session) = musicRig(fake)
        defer { r.cleanup() }
        session.acquire("tab")
        #expect(fake.count("start") == 1 && session.isPlaybackRunning)
        r.registry.switches["notchQueue"] = true
        session.release("tab")
        #expect(fake.count("stop") == 0, "a feature still holds it")
        r.registry.switches["notchQueue"] = false
        #expect(fake.count("stop") == 1)
        session.acquire("tab")
        session.release("tab")
        #expect(fake.count("start") == 2 && fake.count("stop") == 2, "a closed tab alone stops the adapter again")
    }

    @Test func theClosedIslandMusicWingFollowsThePlayingTrack() {
        let fake = MusicFake()
        let (r, _) = musicRig(fake)
        defer { r.cleanup() }
        r.registry.switches["notchLyrics"] = true
        fake.onChange?(MusicNowPlaying(title: "Blue in Green", isPlaying: true, progress: 0.25))
        #expect(fake.posted.count == 1)
        #expect(fake.posted.first?.id == "music.port" && fake.posted.first?.priority == .music)
        #expect(fake.posted.first?.source == "notchLyrics", "withdrawn with its feature")
        fake.onChange?(MusicNowPlaying(title: "Blue in Green", isPlaying: false, progress: 0.25))
        #expect(fake.withdrawn.last == "music.port", "paused: the wing goes")
        fake.onChange?(nil)
        #expect(fake.withdrawn.filter { $0 == "music.port" }.count >= 2)
    }

    @Test func equalizerStartsAndStopsItsOwnService() {
        let fake = MusicFake()
        let (r, _) = musicRig(fake)
        defer { r.cleanup() }
        r.registry.switches["notchLiveEqualizer"] = true
        #expect(fake.events.contains("eq") && fake.count("start") == 1)
        r.registry.switches["notchLiveEqualizer"] = false
        #expect(fake.events.contains("eq.stop"))
    }

    @Test func theKillSwitchStopsEveryMusicFeatureAndTheAdapter() {
        let fake = MusicFake()
        let (r, session) = musicRig(fake)
        defer { r.cleanup() }
        for id in ["notchLyrics", "notchQueue", "notchLiveEqualizer"] { r.registry.switches[id] = true }
        #expect(session.isPlaybackRunning)
        r.registry.killSwitch = true
        #expect(fake.count("stop") == 1 && session.isPlaybackRunning == false)
        #expect(fake.events.contains("lyrics.stop") && fake.events.contains("eq.stop"))
        #expect(PortHost.hostsIslandFeatures == false)
        #expect(r.binding.availability("notchLyrics") == false, "the ported gates read the registry verdict")
    }

    // MARK: Timer, calendar, accessories, notifications

    func timerRig(_ fake: TimerFake, accessibility: Box<Bool> = Box(true)) -> Rig {
        rig(accessibility: accessibility) { TimerLane.bind(into: $0, runtime: fake.runtime()) }
    }

    @Test func theFourFeaturesAreNewDescriptorsOffByDefaultWithTheirPermissions() {
        let fake = TimerFake()
        let r = timerRig(fake)
        defer { r.cleanup() }
        let ids = ["notchTimer", "notchCalendar", "notchAccessories", "notchNotifications"]
        #expect(r.binding.descriptors.map(\.id) == ids)
        for descriptor in r.binding.descriptors {
            #expect(descriptor.enabledByDefault == false && descriptor.category == .island)
            #expect(r.registry.state(for: descriptor.id) == .off)
        }
        #expect(r.registry.descriptor("notchCalendar")?.permissions == [.calendar])
        #expect(r.registry.descriptor("notchNotifications")?.permissions == [.accessibility])
        #expect(fake.events.isEmpty)
    }

    @Test func eachFeatureStartsItsServiceOnceAndStopsItAndTheHostingFlagFollows() {
        let fake = TimerFake()
        let r = timerRig(fake)
        defer { r.cleanup() }
        r.registry.switches["notchTimer"] = true
        r.registry.switches["notchTimer"] = true
        #expect(fake.events.filter { $0 == "timer" }.count == 1)
        #expect(PortHost.hostsIslandFeatures)
        r.registry.switches["notchAccessories"] = true
        r.registry.switches["notchCalendar"] = true
        #expect(fake.events.contains("accessories") && fake.events.contains("calendar"))
        r.registry.switches["notchTimer"] = false
        #expect(fake.events.contains("timer.stop"))
        #expect(PortHost.hostsIslandFeatures, "accessories and the calendar still host")
        r.registry.switches["notchAccessories"] = false
        r.registry.switches["notchCalendar"] = false
        #expect(PortHost.hostsIslandFeatures == false)
    }

    @Test func mirroredNotificationsWaitForAccessibilityAndNeverPrompt() {
        let fake = TimerFake()
        let granted = Box(false)
        let r = timerRig(fake, accessibility: granted)
        defer { r.cleanup() }
        r.registry.switches["notchNotifications"] = true
        #expect(fake.events.contains("notifications") == false, "no start without the grant: nothing reads, nothing asks")
        granted.value = true
        let none = PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: false)
        let ax = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false)
        r.registry.permissionsChanged(PermissionChange(old: none, new: ax))
        #expect(fake.events.filter { $0 == "notifications" }.count == 1, "the grant restarts it, once")
    }

    @Test func theKillSwitchStopsAllFourAndWithdrawsTheClosedIslandIndicators() {
        let fake = TimerFake()
        let r = timerRig(fake)
        defer { r.cleanup() }
        for id in ["notchTimer", "notchCalendar", "notchAccessories", "notchNotifications"] { r.registry.switches[id] = true }
        r.registry.killSwitch = true
        for stop in ["timer.stop", "calendar.stop", "accessories.stop", "notifications.stop"] {
            #expect(fake.events.contains(stop), "\(stop)")
        }
        #expect(fake.events.contains("withdraw.timer"))
        #expect(PortHost.hostsIslandFeatures == false)
    }

    // MARK: The ported gates and the notice sink, for real

    @Test func theHostedGateOpensTheSixSupportsOnlyWhileALaneHostsAndTheRegistryAllows() {
        PortHostFixture.isolated { defaults in
            PortIslandHosting.reset()
            defer { PortIslandHosting.reset() }
            for feature in [AppFeature.notchTimer, .notchCalendar, .notchAccessories, .notchNotifications, .notchLyrics,
                            .notchQueue] {
                defaults.set(true, forKey: feature.availabilityKey)
            }
            defaults.set(true, forKey: DefaultsKey.notchTimerEnabled)
            defaults.set(true, forKey: DefaultsKey.notchAccessoriesEnabled)
            defaults.set(true, forKey: DefaultsKey.notchLyricsEnabled)
            #expect(NotchTimerSupport.isEnabled(in: defaults) == false, "Vorssaint's island is asleep and nobody hosts")
            #expect(NotchAccessorySupport.isEnabled(in: defaults) == false)
            PortIslandHosting.acquire("test")
            #expect(NotchTimerSupport.isEnabled(in: defaults))
            #expect(NotchAccessorySupport.isEnabled(in: defaults), "the Power monitor switch is not a prerequisite")
            #expect(NotchLyricsSupport.isEnabled(in: defaults))
            #expect(NotchSupport.isEnabled(in: defaults) == false, "everything that needs their window still reads false")
            defaults.set(false, forKey: AppFeature.notchTimer.availabilityKey)
            #expect(NotchTimerSupport.isEnabled(in: defaults) == false, "a switched-off feature stays off")
        }
    }

    @Test func aNoticeOfTheOldIslandReachesOurIslandThroughTheSink() {
        let sink = PortIslandOutput.shared
        let savedPost = sink.post, savedRouted = sink.isRouted
        defer { sink.post = savedPost; sink.isRouted = savedRouted }
        var posted: [(IslandActivity, Duration)] = []
        sink.post = { posted.append(($0, $1)) }
        sink.isRouted = { _ in true }
        let notice = NotchNotice(event: .accessory, title: "AirPods", detail: "Batterie faible · 18%",
                                 symbol: "airpodspro", level: 0.18)
        #expect(NotchService.shared.show(notice), "NotchService.show is the entry the ported services call")
        #expect(posted.count == 1)
        #expect(posted.first?.0.id == "island.notice.accessory")
        #expect(posted.first?.0.leading?.text == "AirPods 18 %")
        sink.isRouted = { _ in false }
        #expect(NotchService.shared.show(notice) == false && posted.count == 1, "a feature that is off posts nothing")
    }

    @Test func aRealTimerStartsOnlyOnceHostedAndSurfacesAsAReadingThenGoesAway() {
        PortHostFixture.isolated { defaults in
            PortIslandHosting.reset()
            defer { NotchTimerService.shared.stop(); PortIslandHosting.reset() }
            defaults.set(true, forKey: AppFeature.notchTimer.availabilityKey)
            defaults.set(true, forKey: DefaultsKey.notchTimerEnabled)
            let service = NotchTimerService.shared
            service.start(mode: .timer, minutes: 1)
            #expect(service.session.hasSession == false, "not hosted: the service is asleep and refuses")
            PortIslandHosting.acquire("test")
            service.syncWithPreferences()
            service.start(mode: .timer, minutes: 1)
            #expect(service.session.isRunning)
            let reading = TimerReading(session: service.session, now: service.now)
            #expect(reading?.phase == .timer && (reading?.seconds ?? 0) > 55)
            service.stop()
            #expect(service.session.hasSession == false)
        }
    }
}
