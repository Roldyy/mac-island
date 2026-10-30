import AgentsFeature
import AppKit
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
import TerminalFeature
import SettingsKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleID = "be.roldy.macisland"
    private static let log = Logger(subsystem: "be.roldy.macisland", category: "migration")
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateVorssaintIfNeeded()  // must run before the clipboard reads its migrated files
        ClipboardFeature.start()
        ShelfFeature.start()
        // Each start() only arms what the user's settings and granted permissions allow; none prompts.
        FinderFeature.start()
        DockFeature.start()
        DisplayFeature.start()
        AudioFeature.start()
        FansFeature.start()  // read-only monitoring; manual control needs the approved helper
        MonitorFeature.start()
        CommandBarFeature.start()
        let island = IslandController { IslandRootView() }
        island.openSize = CGSize(width: 720, height: 420)
        island.show()
        self.island = island

        // The command bar can jump to any tab of the island.
        CommandBarFeature.register(commands: ShellTabs.all.map { tab in
            BarCommand(id: "island.tab.\(tab.id)", title: "Ouvrir \(tab.title)",
                       keywords: ["île", "island", tab.id, tab.title]) { [weak island] in
                ShellState.shared.selected = tab.id
                island?.open()
            }
        })
    }

    /// First launch only: copy the Vorssaint settings across. Never touches the source.
    private func migrateVorssaintIfNeeded() {
        guard let defaults = AppDefaults.make() else { return }
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let migrator = VorssaintMigrator(
            sourceDomain: UserDefaults.standard.persistentDomain(forName: "com.vorssaint.utils") ?? [:],
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

/// The island's tabs, in display order.
@MainActor
enum ShellTabs {
    static let all: [IslandTab] = [
        TerminalFeature.tab(), AgentsFeature.tab(), ClipboardFeature.tab(),
        ShelfFeature.tab(), KeepAwakeFeature.tab(), NowPlayingFeature.tab(),
        FinderFeature.tab(), DockFeature.tab(), DisplayFeature.tab(), AudioFeature.tab(),
        FansFeature.tab(), MonitorFeature.tab(), CommandBarFeature.tab(),
    ]
}

/// Which tab is selected. Shared so the command bar can switch tabs.
@MainActor
final class ShellState: ObservableObject {
    static let shared = ShellState()
    @Published var selected = "terminal"
}

/// Island shell: a tab bar and the selected feature's view. Features only supply `IslandTab`s.
struct IslandRootView: View {
    @EnvironmentObject private var state: IslandState
    @ObservedObject private var shell = ShellState.shared

    private let tabs = ShellTabs.all

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: state.isOpen ? 22 : 10, style: .continuous)
                .fill(ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil && !state.isOpen
                      ? Color.red : Color.black)
            if !state.isOpen, let alert = MonitorFeature.currentAlert {
                // Closed island: a red dot in the right wing while a CPU or memory alert is active.
                HStack {
                    Spacer()
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                        .padding(.trailing, 4).padding(.top, 12)
                        .accessibilityLabel(alert.title)
                }
            }
            if state.isOpen {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        // 13 tabs do not fit with labels: icons only, the selected one shows its name.
                        ForEach(tabs) { tab in
                            Button { shell.selected = tab.id } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.systemImage)
                                    if shell.selected == tab.id { Text(tab.title) }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(shell.selected == tab.id ? Color.white.opacity(0.16) : .clear,
                                            in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(shell.selected == tab.id ? 1 : 0.6))
                            .help(tab.title)
                            .accessibilityLabel(tab.title)
                        }
                        Spacer(minLength: 8)
                        if let alert = MonitorFeature.currentAlert {
                            Label(alert.title, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                                .accessibilityLabel("\(alert.title). \(alert.message)")
                        }
                        if FansFeature.isManualActive {
                            // Manual fan mode outlives the island: always say so while it is on.
                            Label("Ventilos manuels", systemImage: "fan.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.cyan)
                        }
                        ClaudeStatusPill(model: TerminalFeature.claudeStatus())  // hidden while idle
                    }
                    .padding(.top, 38)  // clear of the notch
                    .padding(.bottom, 8)
                    if let tab = tabs.first(where: { $0.id == shell.selected }) {
                        tab.makeView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.isOpen)
        .onChange(of: state.isOpen) { _, open in
            if open { KeepAwakeFeature.noteIslandActivity() }  // honours `notchKeepAwakeActivity`
        }
    }
}
