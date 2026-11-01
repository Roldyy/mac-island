import AppKit
import IslandUI
import SwiftUI

/// Live state of the three permissions the running features depend on, with "Autoriser", "Revérifier" and,
/// when macOS says yes but the process still reads no, the sentence that tells the user to relaunch.
struct PermissionStatusCard: View {
    let registry: FeatureRegistry
    var relaunch: (@MainActor () -> Void)?

    var body: some View {
        if let monitor = registry.permissionMonitor {
            let snapshot = monitor.snapshot
            let stale = monitor.staleSuspected
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                HStack {
                    Text("Autorisations système").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("Revérifier") { monitor.recheck() }.buttonStyle(IslandButtonStyle())
                }
                ForEach(MonitoredPermission.allCases, id: \.self) { permission in
                    HStack(spacing: IslandSpacing.s) {
                        Text(permission.title).font(.system(size: 12))
                        IslandBadge(PermissionHints.state(snapshot[permission]),
                                    status: snapshot[permission] ? .success : .warning)
                        Spacer()
                        if !snapshot[permission] {
                            Button("Autoriser") {
                                monitor.noteOpened(permission)
                                if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(IslandButtonStyle())
                        }
                    }
                }
                if !stale.isEmpty {
                    Text(PermissionHints.stale)
                        .font(.system(size: 11)).foregroundStyle(IslandPalette.textSecondary.color)
                    if let relaunch { Button("Relancer") { relaunch() }.buttonStyle(IslandButtonStyle()) }
                }
            }
        }
    }
}
