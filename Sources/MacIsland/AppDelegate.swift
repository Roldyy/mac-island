import AppKit
import IslandKit
import SettingsKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleID = "be.roldy.macisland"
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateVorssaintIfNeeded()
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

/// Placeholder content: the feature modules plug in here.
struct IslandRootView: View {
    @EnvironmentObject private var state: IslandState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: state.isOpen ? 22 : 10, style: .continuous)
                .fill(ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil && !state.isOpen
                      ? Color.red : Color.black)
            if state.isOpen {
                Text("Mac Island")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.isOpen)
    }
}
