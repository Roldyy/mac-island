import IslandUI
import SwiftUI

/// "Nouveautés": the changelog, newest first.
struct WhatsNewPage: View {
    let page: SettingsPage

    var body: some View {
        SettingsPageScaffold(page: page) {
            ForEach(ChangelogEntry.all) { entry in
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    IslandHeader("v\(entry.version) · \(entry.date)")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: IslandSpacing.m) {
                            group("Ajouts", "plus.circle", entry.added)
                            group("Modifications", "arrow.triangle.2.circlepath", entry.changed)
                            group("Corrections", "wrench", entry.fixed)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ symbol: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                Label(title, systemImage: symbol).font(.islandBodyEmphasis)
                ForEach(lines, id: \.self) { line in
                    Text("• " + line).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
    }
}
