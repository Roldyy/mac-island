import AgentsFeature
import AppKit
import ClipboardFeature
import IslandKit
import TerminalFeature
import SettingsKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleID = "be.roldy.macisland"
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateVorssaintIfNeeded()  // must run before the clipboard reads its migrated files
        ClipboardFeature.start()
        let island = IslandController { IslandRootView() }
        island.show()
        self.island = island
    }

    /// First launch only: copy the Vorssaint settings across. Never touches the source.
    private func migrateVorssaintIfNeeded() {
        guard let defaults = UserDefaults(suiteName: Self.bundleID) else { return }
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
                for key in report.unknownKeys { NSLog("MacIsland: unmapped Vorssaint key: %@", key) }
            }
        } catch {
            NSLog("MacIsland: migration aborted, nothing was changed: %@", "\(error)")
        }
    }
}

/// Island shell: a tab bar and the selected feature's view. Features only supply `IslandTab`s.
struct IslandRootView: View {
    @EnvironmentObject private var state: IslandState
    @State private var selected = "terminal"

    private let tabs: [IslandTab] = [
        TerminalFeature.tab(), AgentsFeature.tab(), ClipboardFeature.tab(),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: state.isOpen ? 22 : 10, style: .continuous)
                .fill(ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil && !state.isOpen
                      ? Color.red : Color.black)
            if state.isOpen {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { tab in
                            Button { selected = tab.id } label: {
                                Label(tab.title, systemImage: tab.systemImage)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(selected == tab.id ? Color.white.opacity(0.16) : .clear,
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(selected == tab.id ? 1 : 0.6))
                        }
                    }
                    .padding(.top, 38)  // clear of the notch
                    .padding(.bottom, 8)
                    if let tab = tabs.first(where: { $0.id == selected }) {
                        tab.makeView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.isOpen)
    }
}
