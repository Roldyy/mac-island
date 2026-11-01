import AgentsFeature
import AppKit
import ClaudeLiveKit
import ClipboardFeature
import Combine
import CommandBarFeature
import FansFeature
import MonitorFeature
import FinderFeature
import DockFeature
import AudioFeature
import KeepAwakeFeature
import NowPlayingFeature
import Observation
import os
import PortKit
import ShelfFeature
import IslandKit
import ShellKit
import TerminalFeature
import SettingsKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleID = "be.roldy.macisland"
    private static let vorssaintDomain = "com.vorssaint.utils"
    private static let log = Logger(subsystem: "be.roldy.macisland", category: "migration")
    private var island: IslandController?
    private var registry: FeatureRegistry?
    private var settings: SettingsWindowController?
    private var menuBar: MenuBarItemController?
    private var claudeLive: ClaudeLiveMonitor?
    private var systemActions: SystemActions?
    /// The closed island's indicators: Claude, limits, music and alerts arrive through the activity engine;
    /// battery and keep awake post here directly.
    private let ambient = AmbientCenter.shared
    private var battery: BatterySource?
    private var samplerHub: AmbientSamplerHub?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateVorssaintIfNeeded()  // must run before the clipboard reads its migrated files
        let defaults = AppDefaults.make() ?? .standard
        // The ported features: same defaults domain as the registry and the migrator, then every lane binds its
        // features (descriptors the registry needs at init). Nothing starts here.
        PortBridge.configure(defaults: defaults)
        PortBridge.bindLanes()
        let ported = PortFeatureBinding.shared
        let registry = FeatureRegistry(
            descriptors: ShellDescriptors.all + ported.descriptors, defaults: defaults,
            crashMarker: .standard(bundleID: Self.bundleID),
            capabilityProvider: SystemCapabilities.provider(.live(defaults: defaults)))
        // The migrator does not carry the old "kept features" key, so fall back to its source domain.
        registry.seedFromVorssaint(defaults.object(forKey: VorssaintHubSeed.key)
            ?? UserDefaults.standard.persistentDomain(forName: Self.vorssaintDomain)?[VorssaintHubSeed.key])
        // Registry is the only writer of `shell.enabled.*`; the ported code reaches it through these two doors,
        // and reads the permissions from our monitor. Only then are upstream's defaults registered (after the
        // migration and the seed above), so a registered default is never read as a chosen value.
        PortBridge.connectRegistry(
            setEnabled: { id, enabled in MainActor.assumeIsolated { _ = registry.setSwitch(id, to: enabled) } },
            storedSwitch: { id in MainActor.assumeIsolated { registry.storedSwitch(id) } })
        PortBridge.updatePermissions(Self.portPermissions(PermissionProbe.live(defaults: defaults).snapshot()))
        PortBridge.registerDefaults()
        // The one prompt-capable audio call (a probe tap) runs from the "Autoriser" click only.
        UserPermissionRequest.audioCaptureRequest = { PortMixer.requestAudioCaptureByClick() }
        // The Dock tab's "Autoriser" buttons ask like the Settings cards do: once, so macOS lists the app, then the pane.
        PortDock.requestPermission = { permission in
            switch permission {
            case .accessibility: UserPermissionRequest.request(MonitoredPermission.accessibility)
            case .screenRecording: UserPermissionRequest.request(MonitoredPermission.screenRecording)
            }
        }
        // The Finder tab shows the ported engine's state and forwards its two switches; it installs no tap.
        FinderFeature.engineStatus = { .init(running: PortFinder.isRunning, cutCount: PortFinder.cutCount) }
        FinderFeature.engineSync = { PortFinder.syncPreferences() }
        FinderFeature.engineCancelCut = { PortFinder.cancelCut() }
        // Now Playing talks to two players: its own ask (the running one, then the pane after a refusal) answers the click.
        UserPermissionRequest.automationHandlers["nowplaying"] = { NowPlayingFeature.requestAutomationFromHome() }
        // The OCR page's own "Autoriser": ask once so macOS lists the app, then open the pane.
        PortCaptureTools.requestPermission = { _ in UserPermissionRequest.request(MonitoredPermission.screenRecording) }

        // Claude Code sessions (any terminal or VS Code) feed the closed island through the activity engine.
        let live = ClaudeLiveMonitor(
            source: ClaudeLiveSource(reader: ClaudeSessionReader(directory: ClaudeSessionReader.defaultDirectory)),
            sink: ActivityCenterSink())
        claudeLive = live

        // Each start() only arms what the user's settings and granted permissions allow; none prompts.
        // From here the registry also stops them: kill switch, safe mode and each switch call the stoppers.
        // Now Playing exposes no stop(): its switch takes effect at the next launch and the Settings row says so.
        // The ported features add their own starters and stoppers (permission-gated, never prompting).
        // Crash recovery runs FIRST (PortBridge.launchAfterRecovery): a feature that started before it would write
        // its own journal and the recovery would undo it as if a crash had left it.
        PortBridge.launchAfterRecovery {
            registry.launch(
                starters: ported.starters.merging([
                    "clipboard": { ClipboardFeature.start() },
                    "shelf": { ShelfFeature.start() },
                    // No "finder" here: the ported Finder engine (cut and paste, rename) owns its key taps now and
                    // the bound starter runs it. Our module's tab only displays its state (`FinderFeature.engine*`).
                    // No "fans" here either: the bound Fans lane starts and stops the policy.
                    "monitor": { MonitorFeature.start() },
                    "nowplaying": { NowPlayingFeature.start() },
                    "agents": { live.start() },
                ]) { _, ours in ours },
                stoppers: ported.stoppers.merging([
                    "shelf": { ShelfFeature.stop() },  // the ported shelf's own stop, then the Downloads watcher
                    "monitor": { MonitorFeature.stop() },
                    "agents": { live.stop() },  // withdraws every Claude activity through the sink
                ]) { _, ours in ours },
                activitySources: ["agents": ClaudeActivityMapper.source])
        }
        self.registry = registry
        // One writer for Scratchpad.json: while the ported Scratchpad runs, the Clipboard tab's pane is read-only.
        ClipboardFeature.portedScratchpadRunning = {
            registry.descriptor("scratchpad") != nil && registry.isEnabled("scratchpad")
        }
        // Re-reads Accessibility, Input Monitoring and Screen Recording on activation, on the system
        // notification and on a slow poll (2.5 s, backing off) while one is missing; starts or stops the
        // features that use it. Every reading is copied to the ported code before the registry reacts.
        let monitor = PermissionMonitor.attachLive(to: registry, probe: .live(defaults: defaults))
        monitor.addSnapshotObserver { PortBridge.updatePermissions(Self.portPermissions($0)) }

        let tabs = ShellTabs.all
        let navigation = ShellNavigation()
        let quickAccess = QuickAccessModel(defaults: defaults)
        let settings = SettingsWindowController(
            registry: registry, tabs: tabs,
            openPermission: { permission in UserPermissionRequest.request(permission) },
            relaunch: Self.relaunchAction)
        self.settings = settings
        installPortBridge(settings: settings)
        KeepAwakeShortcutService.shared.arm(defaults: defaults) { KeepAwakeFeature.toggle() }
        // A click on the icon opens the quick panel (ported menu panel); a right click keeps the menu. The island
        // closes first so two surfaces never stack.
        PortQuickPanel.shared.willShow = { [weak self] in MainActor.assumeIsolated { self?.island?.close() } }
        menuBar = MenuBarItemController(
            onOpenSettings: { settings.show() },
            onQuit: { NSApp.terminate(nil) },
            onRelaunch: Self.relaunchAction,
            onTogglePanel: { button in PortQuickPanel.shared.toggle(from: button) },
            defaults: defaults)
        // The ported menu bar metrics may hide the app's icon (their option), only while one of their items shows.
        PortMenuBar.installAppIconVisibility { [weak self] visible in self?.menuBar?.setIconVisible(visible) }

        let home = HomeModel(defaults: defaults)
        let ambientCenter = ambient
        weak var islandRef: IslandController?  // weak: the island owns this context
        let context = ShellContext(
            tabs: tabs, registry: registry, navigation: navigation, quickAccess: quickAccess, home: home,
            closedStrip: { AnyView(ClosedStrip(ambient: ambientCenter)) },
            alert: { MonitorFeature.currentAlert.map { ShellAlert(title: $0.title, message: $0.message) } },
            manualFansActive: { FansFeature.isManualActive },
            claudePill: { AnyView(ClaudeStatusPill(model: TerminalFeature.claudeStatus())) },
            openSettings: { settings.show() },
            onOpen: { KeepAwakeFeature.noteIslandActivity() },  // honours `notchKeepAwakeActivity`
            onOpenSize: { size in
                // Width first (openSize is read by the next open), then the height, which moves an open panel.
                islandRef?.openSize.width = size.width
                islandRef?.setOpenHeight(size.height)
            },
            quit: { NSApp.terminate(nil) },
            relaunch: Self.relaunchAction)
        // The panel measures the ambient center's width proxy, not the raw activity layout: two indicators per
        // wing need more room than the arbiter's one item per wing says.
        let island = IslandController(activityCenter: ambientCenter.widthProxy) { IslandShellView(context: context) }
        island.openSize = context.panelSize
        islandRef = island
        island.show()

        // The home's now-playing card reads the players themselves (Now Playing feature), not the closed island.
        home.attachNowPlaying(Self.nowPlayingSource())
        // The island page's editors (size, look, notch fit, round buttons) drive this very model.
        SettingsPageBodies.register(pageID: "island") {
            AnyView(IslandLayoutSettings(home: home, openIsland: { [weak island] in island?.open() }))
        }
        AgentsFeature.startResting()  // limits wing at rest, when notchIdleContent is "agents"
        startAmbientSources(live: live)
        self.island = island

        // The six quick-access buttons. Each one acts or opens the System Settings pane it needs.
        let actions = SystemActions(closeIsland: { [weak island] in island?.close() })
        systemActions = actions
        let table = quickAccess.table
        table.register("commands") { actions.showCommands() }
        table.register("capture") { actions.capture() }
        table.register("lockScreen") { actions.lockScreen() }
        table.register("cleaning") { actions.cleaning() }
        table.register("keepawake") { actions.toggleKeepAwake() }
        table.registerState("keepawake") { KeepAwakeFeature.isActive }
        table.register("settings") { settings.show() }

        // The command bar can jump to any tab of the island.
        CommandBarFeature.register(commands: tabs.map { tab in
            BarCommand(id: "island.tab.\(tab.id)", title: "Ouvrir \(tab.title)",
                       keywords: ["île", "island", tab.id, tab.title]) { [weak island] in
                navigation.open(tabID: tab.id)  // any panel opens in the island, grouped or not
                island?.open()
            }
        })
    }

    // MARK: - Closed island indicators

    /// Event-driven sources only: IOKit's power notification, Observation on the keep-awake plan and on the
    /// Claude sessions, the screen-change notification. Nothing polls and nothing asks for a permission.
    private func startAmbientSources(live: ClaudeLiveMonitor) {
        syncNotch()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNotch() }
        }
        let battery = BatterySource(center: ambient)
        battery.start()
        self.battery = battery
        // Clock, system, network, disk, mic, camera, volume: each runs only while its channel is on and the closed
        // strip is on screen (the hub starts and stops them from the center's demand).
        let hub = AmbientSamplerHub(center: ambient, samplers: AmbientSamplers.standard(center: ambient))
        hub.start()
        samplerHub = hub
        observeKeepAwake()
        observeClaude(live)
    }

    /// Same screen as `IslandController` (the notched one when there is one, otherwise the main screen) and the
    /// same test as its geometry (`NotchGeometry.idle`): the notched variant of the strip is drawn only when the
    /// island really sits around a hardware notch. The island never moves to an external display while a
    /// notched built-in screen is connected, so the empty middle there is the real notch.
    private func syncNotch() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { ambient.isNotched = false; return }
        ambient.isNotched = NotchGeometry.idle(
            screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea).hasNotch
    }

    private func observeKeepAwake() {
        let active = withObservationTracking({ KeepAwakeFeature.isActive }, onChange: { [weak self] in
            // Fires just before the change lands; the next main-actor turn sees the new value.
            Task { @MainActor in self?.observeKeepAwake() }
        })
        // The center builds the cup (accent while active, dimmed when "Toujours afficher la tasse" is on).
        ambient.setKeepAwake(active: active)
    }

    private func observeClaude(_ live: ClaudeLiveMonitor) {
        let (sample, open) = withObservationTracking({
            (ClaudeWing.pick(ClosedStrip.samples(live.sessions)), live.sessions.contains { $0.state != .unknown })
        }, onChange: { [weak self, weak live] in
            Task { @MainActor in
                guard let self, let live else { return }
                self.observeClaude(live)
            }
        })
        ambient.setClaude(sample)
        // Idle sessions count: the glyph at rest carries a state dot while any session is open.
        ambient.setClaudeSessionOpen(open)
    }

    /// Cleaning mode must never outlive the app.
    func applicationWillTerminate(_ notification: Notification) { PortCleaningMode.stop() }

    /// Clicking the app again (Finder, Dock, `open`) opens Settings: the app has no other window to show.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return true
    }

    /// Re-applies permissions the user may have just granted in System Settings.
    func applicationDidBecomeActive(_ notification: Notification) { registry?.refreshCapabilities() }

    /// Starts a fresh instance of the app, then quits this one. Only possible from an app bundle.
    private static var relaunchAction: (@MainActor () -> Void)? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return nil }
        return {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                guard error == nil else { return }
                Task { @MainActor in NSApp.terminate(nil) }
            }
        }
    }

    /// First launch only: copy the Vorssaint settings across. Never touches the source.
    private func migrateVorssaintIfNeeded() {
        guard let defaults = AppDefaults.make() else { return }
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let migrator = VorssaintMigrator(
            sourceDomain: UserDefaults.standard.persistentDomain(forName: Self.vorssaintDomain) ?? [:],
            sourceSupportDir: support.appendingPathComponent("com.vorssaint.utils"),
            destDefaults: defaults,
            destSupportDir: support.appendingPathComponent(Self.bundleID))
        do {
            let report = try migrator.run()
            if !report.alreadyDone && !report.nothingToMigrate {
                NSLog("MacIsland: migrated %d keys, %d unknown (names logged below)",
                      report.migratedKeys.count, report.unknownKeys.count)
                // Key names and paths stay out of the readable system log.
                for key in report.unknownKeys { Self.log.info("unmapped Vorssaint key: \(key, privacy: .private)") }
                for link in report.skippedLinks { Self.log.info("skipped symbolic link: \(link, privacy: .private)") }
            }
            // Pass 2: the rest of the known Vorssaint keys, backed up first, never overwriting ours.
            let v2 = try migrator.runV2()
            NSLog("MacIsland: migration v2 carried %d keys, %d switches, %d type mismatches",
                  v2.carriedKeys.count, v2.mappedSwitches.count, v2.typeMismatchKeys.count)
        } catch {
            // `MigrationError.partial` states what was already written (backup path, key count).
            NSLog("MacIsland: migration did not finish: %@", "\(error)")
        }
        // A v2 pass from before the id mapping may have written upstream-named switches: move them once.
        let repaired = VorssaintMigrator.repairSwitchIDsV2(in: defaults)
        if repaired > 0 { NSLog("MacIsland: moved %d migrated switches to their registry ids", repaired) }
        // The same pass may also have carried the old app's runtime markers: remove them once.
        let purged = VorssaintMigrator.purgeRuntimeKeysV2(in: defaults)
        if purged > 0 { NSLog("MacIsland: removed %d carried runtime markers", purged) }
    }
}

/// The 12 feature tabs, reused as sub-views of the island's four groups and of the Settings sheets.
@MainActor
enum ShellTabs {
    static let all: [IslandTab] = [
        TerminalFeature.tab(), AgentsFeature.tab(), ClipboardFeature.tab(),
        ShelfFeature.tab(), KeepAwakeFeature.tab(), NowPlayingFeature.tab(),
        FinderFeature.tab(), DockFeature.tab(), AudioFeature.tab(),
        FansFeature.tab(), MonitorFeature.tab(), CommandBarFeature.tab(),
    ]
}

/// Bridges Claude sessions to the shared activity engine.
@MainActor
final class ActivityCenterSink: ClaudeActivitySink {
    /// The closed island shows Claude as one indicator with its clock, so the folder name no longer takes the
    /// trailing wing: that frees it for the music title while Claude works.
    func post(_ activity: IslandActivity) {
        var activity = activity
        activity.trailing = nil
        ActivityCenter.shared.post(activity)
    }
    func withdraw(id: String) { ActivityCenter.shared.withdraw(id: id) }
}

extension ClosedStrip {
    /// Working and waiting sessions only; `updatedAt` is when they entered that state.
    static func samples(_ sessions: [ClaudeSession]) -> [ClaudeWorkSample] {
        sessions.compactMap { session in
            switch session.state {
            case .working: ClaudeWorkSample(id: session.id, isWaiting: false, since: session.updatedAt)
            case .waiting: ClaudeWorkSample(id: session.id, isWaiting: true, since: session.updatedAt)
            case .idle, .unknown: nil
            }
        }
    }
}

extension AppDelegate {
    /// Connects the ported Vorssaint code (PortKit) to the shell. Inert: it lends closures and registers the
    /// ported Settings page bodies (none yet); it starts no feature and Vorssaint's own island stays off.
    func installPortBridge(settings: SettingsWindowController) {
        let relaunch = Self.relaunchAction
        PortBridge.install(host: PortBridge.Host(
            openSettings: { MainActor.assumeIsolated { settings.show() } },
            closePanel: { MainActor.assumeIsolated { PortQuickPanel.shared.close() } },
            relaunch: relaunch.map { action in { MainActor.assumeIsolated { action() } } }))
        for pageID in PortBridge.registeredPageIDs {
            SettingsPageBodies.register(pageID: pageID) {
                PortBridge.settingsBody(pageID: pageID) ?? AnyView(EmptyView())
            }
        }
        // A bound feature's page opens with its switch and status, then the ported body.
        if let registry {
            for page in PortFeatureBinding.shared.pages {
                SettingsPageBodies.register(
                    pageID: page.pageID, featureID: page.featureID, registry: registry,
                    openPermission: { permission in UserPermissionRequest.request(permission) },
                    page.body)
            }
        }
    }

    /// ShellKit's reading in the ported code's own type.
    static func portPermissions(_ snapshot: PermissionSnapshot) -> PortPermissionState {
        PortPermissionState(accessibility: snapshot.accessibility, inputMonitoring: snapshot.inputMonitoring,
                            screenRecording: snapshot.screenRecording)
    }
}

extension AppDelegate {
    /// The Home card's source: the Now Playing feature's own reading (Spotify, Music), mapped to ShellKit's plain types.
    @MainActor
    static func nowPlayingSource() -> HomeNowPlayingSource {
        HomeNowPlayingSource(
            read: { homeReading(from: NowPlayingFeature.homeReading()) },
            refresh: { await NowPlayingFeature.refreshForHome() },
            setOpen: { NowPlayingFeature.setHomeOpen($0) },
            send: { command in
                let mapped: NowPlayingHomeCommand = switch command {
                case .previous: .previous
                case .playPause: .playPause
                case .next: .next
                }
                NowPlayingFeature.sendFromHome(mapped)
            },
            authorize: { NowPlayingFeature.requestAutomationFromHome() },
            observe: { NowPlayingFeature.observeHome($0) })
    }

    @MainActor
    static func homeReading(from reading: NowPlayingHomeReading) -> HomeNowPlayingReading {
        let access: HomeNowPlayingReading.Access = switch reading.access {
        case .needsAuthorization: .needsAuthorization
        case .ready: .ready
        case .denied: .denied
        }
        let track = reading.track.map { t in
            HomeTrack(title: t.title, artist: t.artist, artworkData: t.artworkData, isPlaying: t.isPlaying,
                      progress: t.duration > 0 ? min(max(t.position / t.duration, 0), 1) : nil, album: t.album,
                      position: t.position, duration: t.duration > 0 ? t.duration : nil,
                      playerBundleID: t.playerBundleID, playerName: t.playerName)
        }
        let player = reading.runningPlayer.map { HomeNowPlayingReading.Player(bundleID: $0.bundleID, name: $0.name) }
        return HomeNowPlayingReading(access: access, track: track, runningPlayer: player,
                                     diagnostic: reading.diagnostic)
    }
}
