import Combine
import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Wave 8C: downloads and watch as closed-island activities, their binding, the tabs and the shelf's Downloads switches.
/// Fake runtime, fake publishers, fake poster: no folder watcher, no Vision, no window list, no real sleep.
@MainActor
@Suite(.serialized) struct IslandDownloadsLaneTests {
    final class Recorder: IslandActivityPosting {
        var live: [String: IslandActivity] = [:]
        func post(_ activity: IslandActivity, expiresAfter: Duration?) { live[activity.id] = activity }
        func withdraw(id: String) { live.removeValue(forKey: id) }
    }

    func item(_ name: String, fraction: Double?, completed: Bool = false, active: Bool = true) -> NotchDownloadItem {
        NotchDownloadItem(id: name, url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, receivedBytes: 10,
                          fraction: fraction, completed: completed, active: active)
    }

    // MARK: Downloads mapping

    @Test func nothingDownloadingPostsNothing() {
        #expect(IslandDownloadActivity.progress([]) == nil)
        #expect(IslandDownloadActivity.progress([item("a", fraction: 1, completed: true)]) == nil)
        #expect(IslandDownloadActivity.progress([item("a", fraction: 0.5, active: false)]) == nil, "a stalled partial is not activity")
    }

    @Test func oneTransferShowsItsPercentageAndSeveralShowTheirCount() {
        let one = IslandDownloadActivity.progress([item("a", fraction: 0.5)])
        #expect(one?.trailing?.text == "50 %" && one?.leading?.progress == 0.5)
        #expect(one?.priority == .ambient && one?.source == "notchDownloads")
        let two = IslandDownloadActivity.progress([item("a", fraction: 0.2), item("b", fraction: 0.4)])
        #expect(two?.trailing?.text == "2")
        #expect(abs((two?.leading?.progress ?? -1) - 0.3) < 0.0001, "the ring is the mean")
        let unknown = IslandDownloadActivity.progress([item("a", fraction: nil)])
        #expect(unknown?.leading?.progress == nil && unknown?.trailing == nil, "an unknown size shows no number")
        let broken = IslandDownloadActivity.progress([item("a", fraction: .nan), item("b", fraction: 2)])
        #expect(broken?.leading?.progress == 1, "a NaN is ignored and a fraction past 1 is clamped")
    }

    @Test func endingsAreShortFrenchAndOutrankNothingOfClaudes() {
        #expect(IslandDownloadActivity.finished().trailing?.text == "Terminé")
        #expect(IslandDownloadActivity.failed().trailing?.text == "Échec")
        #expect(IslandDownloadActivity.finished().priority < .claudeWorking)
        #expect(IslandDownloadActivity.failed().priority < .claudeWorking)
    }

    @Test func theFeedFollowsTheServiceAndStopWithdrawsEverything() {
        let recorder = Recorder()
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let board = IslandActivityBoard(poster: { recorder }, defaults: { bench.defaults })
        let subject = PassthroughSubject<[NotchDownloadItem], Never>()
        let feed = IslandDownloadsFeed(items: subject.eraseToAnyPublisher(), board: board)
        feed.start()
        feed.start()
        #expect(feed.isRunning)
        subject.send([item("a", fraction: 0.1)])
        #expect(recorder.live["downloads.progress"] != nil)
        subject.send([])
        #expect(recorder.live.isEmpty, "the list emptied: the ring goes")
        feed.arrived()
        #expect(recorder.live["downloads.done"]?.trailing?.text == "Terminé")
        feed.failed()
        #expect(recorder.live["downloads.failed"] != nil)
        feed.stop()
        #expect(recorder.live.isEmpty && !feed.isRunning)
        subject.send([item("b", fraction: 0.9)])
        #expect(recorder.live.isEmpty, "a stopped feed ignores the service")
    }

    // MARK: Watch mapping

    func title(_ outcome: NotchWatchOutcome) -> String { "fini" }

    @Test func aWatchShowsItsReadingAndEndsLoudly() {
        #expect(IslandWatchActivity.activity(state: .idle, headline: "x", title: title) == nil)
        let watching = IslandWatchActivity.activity(state: .watching, headline: "Charge 40 %", title: title)
        #expect(watching?.priority == .ambient && watching?.trailing?.text == "Charge 40 %")
        #expect(IslandWatchActivity.activity(state: .watching, headline: "  \n ", title: title)?.trailing == nil)
        let hidden = IslandWatchActivity.activity(state: .hidden, headline: "", title: title)
        #expect(hidden?.leading?.symbol == "eye.slash" && hidden?.trailing?.text == "Masquée")
        let done = IslandWatchActivity.activity(state: .finished(.changed), headline: "", title: title)
        #expect(done?.priority == .alert && done?.showsDot == true && done?.trailing?.text == "fini")
    }

    @Test func aLongReadingIsCutToFitTheWing() {
        let clipped = IslandWatchActivity.clip(String(repeating: "a", count: 60))
        #expect(clipped?.count == IslandWatchActivity.maximumReading && clipped?.hasSuffix("…") == true)
        #expect(IslandWatchActivity.clip("one\ntwo") == "one two")
        #expect(IslandWatchActivity.clip("") == nil)
    }

    @Test func theWatchFeedPostsAndWithdrawsByState() {
        let recorder = Recorder()
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let board = IslandActivityBoard(poster: { recorder }, defaults: { bench.defaults })
        let subject = PassthroughSubject<(NotchWatchState, String), Never>()
        let feed = IslandWatchFeed(state: subject.eraseToAnyPublisher(), board: board, title: title)
        feed.start()
        subject.send((.watching, "12"))
        #expect(recorder.live["watch.state"]?.trailing?.text == "12")
        subject.send((.finished(.settled), ""))
        #expect(recorder.live["watch.state"]?.priority == .alert)
        subject.send((.idle, ""))
        #expect(recorder.live.isEmpty)
        feed.stop()
    }

    // MARK: Binding

    final class Log { var events: [String] = [] }

    func runtime(_ log: Log) -> IslandDownloadsLane.Runtime {
        IslandDownloadsLane.Runtime(
            startDownloads: { log.events.append("dl.start") }, stopDownloads: { log.events.append("dl.stop") },
            startWatch: { log.events.append("watch.start") }, stopWatch: { log.events.append("watch.stop") })
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func rig(screenRecording: Bool = true) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState(screenRecording: screenRecording) })
        let log = Log()
        IslandDownloadsLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    @Test func bothFeaturesAreNewOffByDefaultAndFrench() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["notchDownloads", "notchWatch"])
        for descriptor in r.binding.descriptors {
            #expect(descriptor.enabledByDefault == false)
            #expect(descriptor.category == .island)
            #expect(!descriptor.title.isEmpty && !descriptor.summary.isEmpty)
        }
        #expect(r.binding.descriptors.last?.permissions.contains(.screenRecording) == true, "the watch reads another app's window")
        #expect(r.log.events.isEmpty, "binding starts nothing")
        #expect(r.registry.state(for: "notchDownloads") == .off)
    }

    @Test func switchingOnStartsOnceAndOffStopsAndTheKillSwitchStopsBoth() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["notchDownloads"] = true
        r.registry.switches["notchWatch"] = true
        r.registry.switches["notchDownloads"] = true
        #expect(r.log.events == ["dl.start", "watch.start"])
        r.registry.killSwitch = true
        #expect(Set(r.log.events.suffix(2)) == ["dl.stop", "watch.stop"])
        #expect(r.binding.availability("notchDownloads") == false && r.binding.availability("notchWatch") == false)
        r.registry.killSwitch = false
        #expect(r.log.events.filter { $0.hasSuffix(".start") }.count == 4, "they come back with the switch")
        r.registry.switches["notchWatch"] = false
        #expect(r.log.events.last == "watch.stop")
    }

    @Test func theWatchNeverStartsWithoutScreenRecordingAndNothingAsksForIt() {
        let r = rig(screenRecording: false)
        defer { r.cleanup() }
        r.registry.switches["notchWatch"] = true
        #expect(r.log.events.isEmpty, "the binding's own gate: never arm, never prompt")
        r.registry.switches["notchDownloads"] = true
        #expect(r.log.events == ["dl.start"], "downloads need no permission")
    }

    // MARK: The host flag and the tabs

    @Test func theHostFlagMakesOnlyTheLaneChecksAnswerYesAndLeavesVorssaintsIslandDown() throws {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let host = IslandActivityHost.shared
        #expect(host.isHosting == false)
        #expect(NotchSupport.islandIsEnabled(in: bench.defaults) == false)
        host.acquire("test.lane")
        defer { host.release("test.lane") }
        #expect(host.isHosting && host.holds("test.lane"))
        #expect(NotchSupport.islandIsEnabled(in: bench.defaults))
        #expect(NotchSupport.isEnabled(in: bench.defaults) == false, "upstream's gate keeps its meaning (the shelf reads it)")
        #expect(PortHost.vorssaintIslandEnabled == false, "one island")
    }

    @Test func theLaneTabsAreFrenchAndNothingSaysSoon() {
        let tabs = IslandPortTabs.laneGroup2()
        #expect(tabs.map(\.id) == ["downloads", "filetools", "watch", "mirror", "companion"])
        #expect(tabs.map(\.title) == ["Téléchargements", "Fichiers", "Surveillance", "Miroir", "Compagnon"])
        #expect(!tabs.contains { $0.title.localizedCaseInsensitiveContains("bient") })
        #expect(Set(tabs.map(\.id)).isDisjoint(with: ShellTabs.sample), "no clash with the 12 existing tab ids")
    }

    // MARK: The shelf's Downloads switches

    @Test func theDownloadsSwitchesAreBackOnTheShelfPageAndReadTheKeysTheSegmentReads() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridge = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/Shelf.swift"), encoding: .utf8)
        #expect(bridge.contains("IslandShelfDownloadsSettings()"), "the shelf page body carries the switches")
        let island = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/IslandDownloads.swift"),
                                encoding: .utf8)
        #expect(island.contains("@AppStorage(\"shelfDownloadsEnabled\")") && island.contains("@AppStorage(\"shelfDownloadsLimit\")"))
        let reader = try String(contentsOf: root.appendingPathComponent("Sources/Features/Shelf/ShelfSettings.swift"), encoding: .utf8)
        #expect(reader.contains("\"shelfDownloadsEnabled\"") && reader.contains("\"shelfDownloadsLimit\""))
        #expect(SettingsLive.controls(for: "shelf") == nil, "a live entry would bring the greyed noted rows back")
    }
}

/// The ids of the tabs `ShellTabs.all` holds today (the app target cannot be imported here).
private enum ShellTabs {
    static let sample: Set<String> = ["terminal", "agents", "clipboard", "shelf", "keepawake", "nowplaying", "finder", "dock",
                                      "audio", "fans", "monitor", "commandbar"]
}
