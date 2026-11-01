import Foundation
import Testing
@testable import NowPlayingFeature

/// Fake of the macOS Automation permission: answers per bundle id and records every ask.
final class FakeAutomation: AutomationChecking, @unchecked Sendable {
    let statuses: Box<[String: AutomationStatus]>
    /// What a click that is allowed to prompt turns the status into (the user pressing Allow).
    let afterPrompt: Box<AutomationStatus?>
    let silentChecks = Box(0)
    let prompts = Box(0)

    init(_ statuses: [String: AutomationStatus], afterPrompt: AutomationStatus? = nil) {
        self.statuses = Box(statuses)
        self.afterPrompt = Box(afterPrompt)
    }

    func status(bundleID: String, askUser: Bool) -> AutomationStatus {
        if askUser {
            prompts.set(prompts.get() + 1)
            if let next = afterPrompt.get() { statuses.set(statuses.get().merging([bundleID: next]) { _, new in new }) }
        } else {
            silentChecks.set(silentChecks.get() + 1)
        }
        return statuses.get()[bundleID] ?? .unknown
    }
}

/// A clock that records what the model asked to wait, then waits a few real milliseconds.
final class CountingClock: @unchecked Sendable {
    let requested = Box<[Duration]>([])
    var sleep: @Sendable (Duration) async -> Void {
        { [requested] duration in
            requested.set(requested.get() + [duration])
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
@Suite struct HomeFeedTests {
    private let spotify = BundleIDs.spotify

    private func model(_ providers: [any NowPlayingProvider], flags: MemoryFlags = MemoryFlags(),
                       automation: FakeAutomation? = nil, running: Set<String> = [],
                       clock: CountingClock = CountingClock(),
                       openPane: @escaping @MainActor (URL) -> Void = { _ in },
                       scripts: Box<[String]> = Box([]),
                       keys: Box<[MediaKey]> = Box([])) -> NowPlayingModel {
        let stub = StubRunning(ids: running)
        return NowPlayingModel(
            providers: providers, defaults: flags, interval: .seconds(1),
            transport: NowPlayingTransport(runner: StubRunner(scripts: scripts, fail: false), running: stub,
                                           postKey: { keys.set(keys.get() + [$0]) }),
            artwork: nil, automation: automation, running: stub, openPane: openPane, sleep: clock.sleep)
    }

    // MARK: silent permission check

    @Test func aPermissionThatAlreadyStandsStartsTheReadingWithoutAnyPrompt() async {
        let p = FakeProvider(spotify, .success(snap(spotify, title: "Reason", playing: true)))
        let automation = FakeAutomation([spotify: .granted])
        let m = model([p], automation: automation, running: [spotify])
        #expect(m.access == .needsAuthorization)
        await m.refreshNow()
        #expect(m.access == .ready)
        #expect(m.snapshot?.title == "Reason")
        #expect(automation.prompts.get() == 0)
        m.setHomeOpen(false)
        m.setBackground(false)
    }

    @Test func neverAskedStaysSilentAndReadsNothing() async {
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let automation = FakeAutomation([spotify: .notAsked])
        let m = model([p], automation: automation, running: [spotify])
        await m.refreshNow()
        #expect(m.access == .needsAuthorization)
        #expect(p.calls.get() == 0)
        #expect(automation.prompts.get() == 0)
        let reading = m.homeReading()
        #expect(reading.access == .needsAuthorization)
        #expect(reading.runningPlayer?.name == "Spotify")
    }

    @Test func refusedIsReportedAsDeniedForTheCard() async {
        let automation = FakeAutomation([spotify: .denied])
        let m = model([FakeProvider(spotify, .failure(.permissionDenied))], automation: automation, running: [spotify])
        await m.refreshNow()
        #expect(m.access == .denied)
        #expect(m.homeReading().access == .denied)
        m.setBackground(false)
    }

    @Test func noPlayerOpenMeansNoCheckAtAll() async {
        let automation = FakeAutomation([spotify: .granted])
        let m = model([FakeProvider(spotify, .success(nil))], automation: automation, running: [])
        await m.refreshNow()
        #expect(automation.silentChecks.get() == 0)
        #expect(m.homeReading().runningPlayer == nil)
    }

    // MARK: the click

    @Test func theClickAsksOnceAndThenReads() async {
        let p = FakeProvider(spotify, .success(snap(spotify, title: "Reason", playing: true)))
        let automation = FakeAutomation([spotify: .notAsked], afterPrompt: .granted)
        let m = model([p], automation: automation, running: [spotify])
        await m.refreshNow()
        #expect(automation.prompts.get() == 0)
        await m.requestAutomation()
        #expect(automation.prompts.get() == 1)
        #expect(m.access == .ready)
        #expect(m.snapshot?.title == "Reason")
        m.setBackground(false)
    }

    @Test func aRefusalOpensTheAutomationPane() async {
        let opened = Box<[URL]>([])
        let automation = FakeAutomation([spotify: .denied])
        let m = model([FakeProvider(spotify, .failure(.permissionDenied))], automation: automation,
                      running: [spotify], openPane: { opened.set(opened.get() + [$0]) })
        await m.requestAutomation()
        #expect(m.access == .denied)
        #expect(opened.get() == [AutomationPane.url])
        #expect(AutomationPane.url.absoluteString.hasSuffix("Privacy_Automation"))
        m.setBackground(false)
    }

    // MARK: polling while the home is open

    @Test func theHomePollsFastEvenWhenTheClosedIslandHasNothingToShow() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let flags = MemoryFlags()
        flags.set(true, forKey: "nowplaying.automationRequested")
        let m = model([p], flags: flags, automation: nil, running: [spotify], clock: clock)
        // No background (no closed-pill wing), no tab: nothing polls.
        try? await Task.sleep(for: .milliseconds(40))
        #expect(p.calls.get() == 0)
        m.setHomeOpen(true)
        #expect(await eventually { clock.requested.get().count >= 3 })
        #expect(Set(clock.requested.get()) == [.seconds(1)])
        m.setHomeOpen(false)
        try? await Task.sleep(for: .milliseconds(40))
        let calls = p.calls.get()
        try? await Task.sleep(for: .milliseconds(60))
        #expect(p.calls.get() == calls, "closed and not background: no poll at all")
    }

    @Test func closingTheHomeFallsBackToTheSlowBackgroundPoll() async {
        let clock = CountingClock()
        let flags = MemoryFlags()
        flags.set(true, forKey: "nowplaying.automationRequested")
        let m = model([FakeProvider(spotify, .success(nil))], flags: flags, running: [spotify], clock: clock)
        m.setBackground(true)
        m.setHomeOpen(true)
        #expect(await eventually { clock.requested.get().count >= 2 })
        m.setHomeOpen(false)
        clock.requested.set([])
        #expect(await eventually { clock.requested.get().count >= 2 })
        #expect(Set(clock.requested.get()) == [.seconds(3)])
        m.setBackground(false)
    }

    @Test func openWithoutPermissionOnlyChecksSilentlyEverySecond() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let automation = FakeAutomation([spotify: .notAsked])
        let m = model([p], automation: automation, running: [spotify], clock: clock)
        m.setHomeOpen(true)
        #expect(await eventually { automation.silentChecks.get() >= 3 })
        #expect(p.calls.get() == 0)
        #expect(automation.prompts.get() == 0)
        // The permission is granted from System Settings while the home is open: the card picks it up by itself.
        automation.statuses.set([spotify: .granted])
        #expect(await eventually { m.access == .ready && m.snapshot != nil })
        m.setHomeOpen(false)
    }

    @Test func observersHearEveryReadingAndTheCoverArriving() async {
        let p = FakeProvider(spotify, .success(snap(spotify, title: "Reason", playing: true)))
        let m = NowPlayingModel(providers: [p], defaults: MemoryFlags(), interval: .milliseconds(10), transport: nil,
                                artwork: FakeLoader(delays: [:]))
        let heard = Box(0)
        m.addObserver { heard.set(heard.get() + 1) }
        await m.authorize()
        #expect(await eventually { m.artwork == Data("Reason".utf8) })
        #expect(heard.get() >= 2)
        #expect(m.homeReading().track?.artworkData == Data("Reason".utf8))
        #expect(m.homeReading().track?.playerName == "Spotify")
    }

    // MARK: transport

    @Test func playOnAnOpenPlayerWithNothingLoadedUsesItsOwnScriptNotAMediaKey() async {
        let scripts = Box<[String]>([])
        let keys = Box<[MediaKey]>([])
        let m = model([FakeProvider(spotify, .success(nil))], running: [spotify], scripts: scripts, keys: keys)
        m.send(.playPause)
        #expect(await eventually { !scripts.get().isEmpty })
        #expect(scripts.get().first?.contains("playpause") == true)
        #expect(keys.get().isEmpty)
    }

    @Test func aPausedTrackIsReadAsPausedNotDropped() async {
        let p = FakeProvider(spotify, .success(snap(spotify, title: "Reason", playing: false)))
        let flags = MemoryFlags()
        flags.set(true, forKey: "nowplaying.automationRequested")
        let m = model([p], flags: flags, running: [spotify])
        await m.poll()
        let reading = m.homeReading()
        #expect(reading.track?.title == "Reason")
        #expect(reading.track?.isPlaying == false)
    }
}
