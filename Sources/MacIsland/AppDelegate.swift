import AgentsFeature
import AppKit
import ClaudeLiveKit
import ClipboardFeature
import CommandBarFeature
import FansFeature
import MonitorFeature
import FinderFeature
import DockFeature
import DisplayFeature
import AudioFeature
import KeepAwakeFeature
import NowPlayingFeature
import os
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
        menuBar = MenuBarItemController(
            onOpenSettings: { settings.show() },
            onQuit: { NSApp.terminate(nil) })

        weak var islandRef: IslandController?  // weak: the island owns this context
        let context = ShellContext(
            tabs: tabs, registry: registry, navigation: navigation, quickAccess: quickAccess,
            closedStrip: { AnyView(ClosedStrip()) },
            onSectionChange: { id in islandRef?.setOpenHeight(ShellLayout.openHeight(forSection: id)) },
            alert: { MonitorFeature.currentAlert.map { ShellAlert(title: $0.title, message: $0.message) } },
            manualFansActive: { FansFeature.isManualActive },
            claudePill: { AnyView(ClaudeStatusPill(model: TerminalFeature.claudeStatus())) },
            openSettings: { settings.show() },
            onOpen: { KeepAwakeFeature.noteIslandActivity() })  // honours `notchKeepAwakeActivity`
        let island = IslandController { IslandShellView(context: context) }
        island.openSize = CGSize(width: 720, height: ShellLayout.defaultOpenHeight)
        islandRef = island
        island.show()
        AgentsFeature.startResting()  // limits wing at rest, when notchIdleContent is "agents"
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
                if navigation.select(tabID: tab.id) { island?.open() } else { settings.show() }
            }
        })
    }

    /// Cleaning mode must never outlive the app.
    func applicationWillTerminate(_ notification: Notification) { FinderFeature.endCleaning() }

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
        } catch {
            // `MigrationError.partial` states what was already written (backup path, key count).
            NSLog("MacIsland: migration did not finish: %@", "\(error)")
        }
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
    func post(_ activity: IslandActivity) { ActivityCenter.shared.post(activity) }
    func withdraw(id: String) { ActivityCenter.shared.withdraw(id: id) }
}

/// The closed island's wings, redrawn whenever the activity engine publishes a new layout.
/// The notch width comes from the environment, so the view holds no reference to the island.
struct ClosedStrip: View {
    @EnvironmentObject private var state: IslandState
    @ObservedObject private var center = ActivityCenter.shared
    var body: some View { CompactStrip(layout: center.layout, notchWidth: state.notchWidth) }
}
