import Foundation
import IslandKit
import IslandTestSupport
import Testing
import UserNotifications
@testable import PortKit
@testable import ShellKit

/// The wiring of the merged lanes into the app: the island's panels and their switches, the gesture hooks and their kill
/// switch, the Now Playing adapter in the bundle, and the two permission cards that ask by click.
@MainActor
@Suite(.serialized) struct IslandWiringTests {
    private static func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: Panels

    @Test func everyPortedPanelHasAGateAndEveryGateSwitchIsARealRegistryFeature() {
        let panels = [PortIslandMusic.tab()]
            + [PortIslandTimer.timerTab(), PortIslandTimer.calendarTab(),
               PortIslandTimer.notificationsTab(), PortIslandTimer.accessoriesTab()]
            + IslandPortTabs.laneGroup2()
        #expect(panels.map(\.id) == ["music", "timer", "calendar", "notifications", "accessories",
                                     "downloads", "filetools", "watch", "mirror", "companion"])
        #expect(Set(panels.map(\.id)) == Set(ShellTabGate.ported.features.keys))
        #expect(!panels.contains { $0.title.localizedCaseInsensitiveContains("bient") })

        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        PortLanes.bindAll(into: binding)
        let known = Set(ShellDescriptors.all.map(\.id)).union(binding.descriptors.map(\.id))
        for (tab, switches) in ShellTabGate.ported.features {
            #expect(!switches.isEmpty, Comment(rawValue: tab))
            for id in switches { #expect(known.contains(id), "\(tab) is gated by \(id), which is no registry feature") }
        }
    }

    @Test func noPanelClashesWithTheTwelveFirstOnes() {
        let first = Set(ShellDescriptors.all.compactMap(\.tabID))
        #expect(first.isDisjoint(with: ShellTabGate.ported.features.keys))
        #expect(!ShellLayout.isDailyPage("music"), "the nine daily pages stay as they are")
    }

    @Test func theAppDelegateAppendsThePanelsAndPassesTheGate() throws {
        let text = try Self.source("Sources/MacIsland/AppDelegate.swift")
        for needle in ["PortIslandMusic.tab()", "PortIslandTimer.timerTab()", "PortIslandTimer.calendarTab()",
                       "PortIslandTimer.notificationsTab()", "PortIslandTimer.accessoriesTab()",
                       "IslandPortTabs.laneGroup2()", "tabGate: .ported", "static let all: [IslandTab] = base + ported"] {
            #expect(text.contains(needle), Comment(rawValue: needle))
        }
    }

    @Test func theClosedIslandStillShowsOnlyTheListedIndicators() throws {
        let text = try Self.source("Sources/MacIsland/AppDelegate.swift")
        // The companion reaches the closed strip only through its opt-in indicator (`IslandMascotPresence`), never by the
        // app delegate drawing it: off, the strip keeps the five default indicators.
        #expect(!text.contains("IslandMascotView"), "the app delegate draws no companion itself")
        let extras = try Self.source("Sources/PortKit/Bridge/IslandLockScreen.swift")
        #expect(extras.contains("struct PortIslandExtrasSettings"))
    }

    // MARK: Gestures

    @Test func theGestureHostFillsBothHooksAndTheKillSwitchCutsThem() {
        let bench = TestDefaults.make()
        defer { bench.cleanup(); PortIslandGestureHost.uninstall() }
        var performed: [PortIslandGestureAction] = []
        let spot = PortIslandGestureSpot(frame: CGRect(x: 0, y: 0, width: 300, height: 40), expanded: false,
                                         overHeader: true, musicSurface: false)
        PortIslandGestureHost.install(defaults: bench.defaults, spot: { spot }, perform: { performed.append($0) })
        #expect(IslandGestures.context?() == IslandGestureContext(frame: spot.frame, expanded: false, overHeader: true,
                                                                  musicSurface: false))
        IslandGestures.perform?(.open)
        IslandGestures.perform?(.nextTrack)
        #expect(performed == [.openIsland, .nextTrack])

        bench.defaults.set(true, forKey: PortIslandGestureHost.killKey)
        #expect(PortIslandGestureHost.isKilled(defaults: bench.defaults))
        #expect(IslandGestures.context?() == nil)
        IslandGestures.perform?(.close)
        #expect(performed == [.openIsland, .nextTrack], "killed: nothing runs")

        bench.defaults.set(false, forKey: PortIslandGestureHost.killKey)
        IslandGestures.perform?(.close)
        #expect(performed.last == .closeIsland)

        PortIslandGestureHost.uninstall()
        #expect(IslandGestures.context == nil && IslandGestures.perform == nil)
    }

    @Test func theMonitorActsThroughTheHostAndSwipeDownOpens() {
        let bench = TestDefaults.make()
        defer { bench.cleanup(); PortIslandGestureHost.uninstall() }
        var performed: [PortIslandGestureAction] = []
        PortIslandGestureHost.install(
            defaults: bench.defaults,
            spot: { PortIslandGestureSpot(frame: CGRect(x: 0, y: 0, width: 300, height: 40), expanded: false,
                                          overHeader: true, musicSurface: false) },
            perform: { performed.append($0) })
        let monitor = IslandGestureMonitor()
        func sample(t: Double, began: Bool) -> IslandScrollSample {
            IslandScrollSample(deltaX: 0, deltaY: 10, precise: true, inverted: true, timestamp: t, began: began,
                               ended: false, momentum: false, hasPhase: true, location: CGPoint(x: 10, y: 10),
                               plainModifiers: true)
        }
        monitor.receive(sample(t: 1, began: true))
        monitor.receive(sample(t: 1.01, began: false))
        #expect(performed == [.openIsland])
    }

    @Test func theAppDelegateInstallsTheGestureHooks() throws {
        let text = try Self.source("Sources/MacIsland/AppDelegate.swift")
        #expect(text.contains("PortIslandGestureHost.install("))
        #expect(text.contains("case .openIsland: island?.open()") && text.contains("case .closeIsland: island?.close()"))
        #expect(text.contains("NowPlayingFeature.sendFromHome(forward ? .next : .previous)"))
    }

    // MARK: Bundle

    @Test func theBundleCarriesTheNowPlayingAdapterSignedBeforeTheApp() throws {
        let script = try Self.source("scripts/bundle.sh")
        #expect(script.contains("libMacIslandNowPlaying.dylib"))
        #expect(script.contains("Contents/Frameworks") && script.contains("Resources/now-playing.pl"))
        let sign = try #require(script.range(of: "Contents/Frameworks/libMacIslandNowPlaying.dylib\"\n"))
        let app = try #require(script.range(of: "--entitlements Resources/MacIsland.entitlements"))
        #expect(script.range(of: "codesign --force $RT $TS -s \"$IDENTITY\" -i \"be.roldy.macisland.nowplaying\"") != nil)
        #expect(sign.lowerBound < app.lowerBound, "the dylib is signed before the app seals it")
        #expect(script.contains("--options runtime"))
        // The adapter is a product of the package (never linked into the app).
        let package = try Self.source("Package.swift")
        #expect(package.contains("\"MacIslandNowPlaying\", type: .dynamic, targets: [\"NowPlayingAdapter\"]"))
        let locator = try Self.source("Sources/PortKit/Bridge/PrivateMediaRemoteAdapter.swift")
        #expect(locator.contains("privateFrameworksURL") && locator.contains("withExtension: \"pl\""))
        #expect(FileManager.default.fileExists(atPath: PortSourceScrubTests.repoRoot
            .appendingPathComponent("Resources/now-playing.pl").path))
    }

    @Test func noLibraryValidationEntitlementIsNeededBecausePerlLoadsTheLibraryNotTheApp() throws {
        let entitlements = try #require(NSDictionary(contentsOf: PortSourceScrubTests.repoRoot
            .appendingPathComponent("Resources/MacIsland.entitlements")) as? [String: Any])
        #expect(entitlements["com.apple.security.cs.disable-library-validation"] == nil)
        // The app never links the adapter: no target of the app depends on NowPlayingAdapter.
        let package = try Self.source("Package.swift")
        let start = try #require(package.range(of: ".executableTarget(name: \"MacIsland\""))
        let end = try #require(package.range(of: "mac-island-migrate", range: start.upperBound..<package.endIndex))
        #expect(!package[start.lowerBound..<end.lowerBound].contains("NowPlayingAdapter"))
    }

    // MARK: Permission cards

    private func descriptor(_ id: String, _ permission: FeaturePermission) -> FeatureDescriptor {
        FeatureDescriptor(id: id, title: id, summary: "x", systemImage: "star", category: .tools, permissions: [permission])
    }

    @Test func theEqualizerAndNotificationCardsAskWhenTheirGrantIsMissing() {
        let missing = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil },
                                      audioCapture: { false }, notifications: { false })
        #expect(SystemCapabilities.capability(for: descriptor("notchLiveEqualizer", .audioCapture), probe: missing)
                == .needsPermission(.audioCapture))
        #expect(SystemCapabilities.capability(for: descriptor("notchWatch", .notifications), probe: missing)
                == .needsPermission(.notifications))
        let granted = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil },
                                      audioCapture: { true }, notifications: { true })
        #expect(SystemCapabilities.capability(for: descriptor("notchLiveEqualizer", .audioCapture), probe: granted) == .available)
        #expect(SystemCapabilities.capability(for: descriptor("notchWatch", .notifications), probe: granted) == .available)
        let unknown = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        #expect(SystemCapabilities.capability(for: descriptor("a", .audioCapture), probe: unknown) == .available,
                "no reading: never a card that cannot be answered")
    }

    @Test func theAudioReadingIsTheStoredOutcomeOfTheClickProbeAndNilWithoutABundleDescription() {
        #expect(PermissionProbe.audioCaptureReading(evidence: nil, hasUsageDescription: true) == false)
        #expect(PermissionProbe.audioCaptureReading(evidence: 0, hasUsageDescription: true) == true)
        #expect(PermissionProbe.audioCaptureReading(evidence: 1_970_171_760, hasUsageDescription: true) == false)
        #expect(PermissionProbe.audioCaptureReading(evidence: 0, hasUsageDescription: false) == nil)
        #expect(PermissionProbe.audioCaptureEvidenceKey == MixerAudioCapture.evidenceKey, "the very key the click writes")
    }

    @Test func aMissingGrantNeverStopsTheFeatureItsCardIsAbout() {
        let state = FeatureState.needsPermission(.audioCapture)
        #expect(state.isEnabled, "still started: its start() arms only what is granted")
    }

    @Test func theNotificationClickAsksThroughUserPermissionRequestAndNothingElseDoes() {
        let saved = (UserPermissionRequest.notificationsAsk, UserPermissionRequest.afterNotificationsAnswer)
        defer { (UserPermissionRequest.notificationsAsk, UserPermissionRequest.afterNotificationsAnswer) = saved }
        var asked = 0
        var refreshed = 0
        UserPermissionRequest.notificationsAsk = { done in asked += 1; done(true) }
        UserPermissionRequest.afterNotificationsAnswer = { refreshed += 1 }
        #expect(asked == 0, "installing the hooks asks nothing")
        UserPermissionRequest.request(FeaturePermission.notifications)
        #expect(asked == 1 && refreshed == 1)
    }

    @Test func readingTheNotificationCacheNeverPromptsAndMapsTheStatus() {
        let cache = NotificationAuthorizationCache()
        #expect(cache.granted == nil)
        cache.set(false)
        #expect(cache.granted == false)
        #expect(NotificationAuthorizationCache.reading(for: .authorized) == true)
        #expect(NotificationAuthorizationCache.reading(for: .provisional) == true)
        #expect(NotificationAuthorizationCache.reading(for: .notDetermined) == false)
        #expect(NotificationAuthorizationCache.reading(for: .denied) == false)
    }
}
