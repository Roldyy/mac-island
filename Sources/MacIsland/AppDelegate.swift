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
import DisplayFeature
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
    private var layoutSubscription: AnyCancellable?
    /// The closed island's indicators: Claude, limits, music and alerts arrive through the activity engine;
    /// battery and keep awake post here directly.
    private let ambient = AmbientCenter.shared
    private var battery: BatterySource?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateVorssaintIfNeeded()  // must run before the clipboard reads its migrated files
        let defaults = AppDefaults.make() ?? .standard
        let registry = FeatureRegistry(
            descriptors: ShellDescriptors.all, defaults: defaults,
            crashMarker: .standard(bundleID: Self.bundleID),
            capabilityProvider: SystemCapabilities.provider(.live(defaults: defaults)))
        // The migrator does not carry the old "kept features" key, so fall back to its source domain.
        registry.seedFromVorssaint(defaults.object(forKey: VorssaintHubSeed.key)
            ?? UserDefaults.standard.persistentDomain(forName: Self.vorssaintDomain)?[VorssaintHubSeed.key])

        // Claude Code sessions (any terminal or VS Code) feed the closed island through the activity engine.
        let live = ClaudeLiveMonitor(
            source: ClaudeLiveSource(reader: ClaudeSessionReader(directory: ClaudeSessionReader.defaultDirectory)),
            sink: ActivityCenterSink())
        claudeLive = live

        // Each start() only arms what the user's settings and granted permissions allow; none prompts.
        // From here the registry also stops them: kill switch, safe mode and each switch call the stoppers.
        // Shelf, Clipboard and Now Playing expose no stop(): their switch takes effect at the next launch
        // and the Settings row says so.
        registry.launch(
            starters: [
                "clipboard": { ClipboardFeature.start() },
                "shelf": { ShelfFeature.start() },
                "finder": { FinderFeature.start() },
                "dock": { DockFeature.start() },
                "display": { DisplayFeature.start() },
                "audio": { AudioFeature.start() },
                "fans": { FansFeature.start() },  // read-only monitoring; manual control needs the approved helper
                "monitor": { MonitorFeature.start() },
                "commandbar": { CommandBarFeature.start() },
                "nowplaying": { NowPlayingFeature.start() },
                "agents": { live.start() },
            ],
            stoppers: [
                "finder": { FinderFeature.stop() },
                "dock": { DockFeature.stop() },
                "display": { DisplayFeature.stop() },
                "audio": { AudioFeature.stop() },
                "fans": { FansFeature.stop() },
                "monitor": { MonitorFeature.stop() },
                "commandbar": { CommandBarFeature.stop() },
                "agents": { live.stop() },  // withdraws every Claude activity through the sink
            ],
            activitySources: ["agents": ClaudeActivityMapper.source])
        self.registry = registry
        // Re-reads Accessibility, Input Monitoring and Screen Recording on activation, on the system
        // notification and on a 1 s poll while one is missing; starts or stops the features that use it.
        PermissionMonitor.attachLive(to: registry, probe: .live(defaults: defaults))

        let tabs = ShellTabs.all
        let navigation = ShellNavigation()
        let quickAccess = QuickAccessModel(defaults: defaults)
        let settings = SettingsWindowController(
            registry: registry, tabs: tabs,
            openPermission: { permission in
                if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
            },
            relaunch: Self.relaunchAction)
        self.settings = settings
        installPortBridge(settings: settings)
        KeepAwakeShortcutService.shared.arm(defaults: defaults) { KeepAwakeFeature.toggle() }
        menuBar = MenuBarItemController(
            onOpenSettings: { settings.show() },
            onQuit: { NSApp.terminate(nil) },
            onRelaunch: Self.relaunchAction)

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

        // The home's now-playing card follows the music wing of the closed island (title and play state only:
        // artwork and artist need a public accessor on the Now Playing feature, which this lane may not add).
        layoutSubscription = ActivityCenter.shared.$layout.sink { layout in
            MainActor.assumeIsolated { home.track = Self.musicTrack(from: layout) }
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
        observeKeepAwake()
        observeClaude(live)
    }

    /// Same rule as `IslandController`: the notched screen when there is one, otherwise the main screen.
    private func syncNotch() {
        ambient.isNotched = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    private func observeKeepAwake() {
        let active = withObservationTracking({ KeepAwakeFeature.isActive }, onChange: { [weak self] in
            // Fires just before the change lands; the next main-actor turn sees the new value.
            Task { @MainActor in self?.observeKeepAwake() }
        })
        if active {
            ambient.post(AmbientIndicator(
                id: "keepawake", channel: AmbientChannel.keepAwake, symbol: "cup.and.saucer.fill", status: .info,
                wing: .trailing, label: "Maintien d’éveil actif"))
        } else {
            ambient.withdraw(id: "keepawake")
        }
    }

    private func observeClaude(_ live: ClaudeLiveMonitor) {
        let sample = withObservationTracking({ ClaudeWing.pick(ClosedStrip.samples(live.sessions)) }, onChange: { [weak self, weak live] in
            Task { @MainActor in
                guard let self, let live else { return }
                self.observeClaude(live)
            }
        })
        ambient.setClaude(sample)
    }

    /// Cleaning mode must never outlive the app.
    func applicationWillTerminate(_ notification: Notification) { FinderFeature.endCleaning() }

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
        // A v2 pass from before the runtime markers were skipped may have carried them: remove them once.
        let purged = VorssaintMigrator.purgeRuntimeKeysV2(in: defaults)
        if purged > 0 { NSLog("MacIsland: removed %d carried runtime markers", purged) }
    }
}

/// The 13 feature tabs, reused as sub-views of the island's four groups and of the Settings sheets.
@MainActor
enum ShellTabs {
    static let all: [IslandTab] = [
        TerminalFeature.tab(), AgentsFeature.tab(), ClipboardFeature.tab(),
        ShelfFeature.tab(), KeepAwakeFeature.tab(), NowPlayingFeature.tab(),
        FinderFeature.tab(), DockFeature.tab(), DisplayFeature.tab(), AudioFeature.tab(),
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
            relaunch: relaunch.map { action in { MainActor.assumeIsolated { action() } } }))
        for pageID in PortBridge.registeredPageIDs {
            SettingsPageBodies.register(pageID: pageID) {
                PortBridge.settingsBody(pageID: pageID) ?? AnyView(EmptyView())
            }
        }
    }
}

extension AppDelegate {
    /// The playing track as far as the closed island's music wing tells it (title only).
    static func musicTrack(from layout: ActivityLayout) -> HomeTrack? {
        guard let item = layout.trailing, item.symbol == "waveform", let title = item.text, !title.isEmpty else { return nil }
        return HomeTrack(title: title, isPlaying: true, progress: layout.leading?.symbol == "music.note" ? layout.leading?.progress : nil)
    }
}
