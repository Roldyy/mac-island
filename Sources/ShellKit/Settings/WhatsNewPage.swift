import AppKit
import IslandUI
import SwiftUI

/// "Nouveautés": the changelog, newest first.
struct WhatsNewPage: View {
    let page: SettingsPage

    var body: some View {
        SettingsPageScaffold(page: page) {
            ForEach(Array(ChangelogEntry.all.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    if index == 0 {
                        Text("Nouveautés de cette version").font(.islandBodyEmphasis)
                    }
                    IslandHeader("v\(entry.version) · \(entry.date)")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: IslandSpacing.m) {
                            if !entry.summary.isEmpty {
                                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                                    Label("Résumé", systemImage: "text.alignleft").font(.islandBodyEmphasis)
                                    Text(entry.summary).font(.islandCaption)
                                        .foregroundStyle(IslandPalette.textSecondary.color)
                                }
                            }
                            group("Ajouts", "plus.circle", entry.added)
                            group("Modifications", "arrow.triangle.2.circlepath", entry.changed)
                            group("Corrections", "wrench", entry.fixed)
                        }
                    }
                }
            }
            RoldyCreditCard(markWidth: 80)
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    Label("Contributeurs", systemImage: "person.2").font(.islandBodyEmphasis)
                    Text("Mac Island reprend le code de Vorssaint 3.4.2 (GPL-3.0). Merci à Vorssaint et à toutes les personnes qui ont contribué à son code, dont la liste est sur sa page GitHub.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Voir les contributeurs sur GitHub", systemImage: "arrow.up.right.square") {
                        if let url = URL(string: "https://github.com/vorssaint/vorssaint-utils/graphs/contributors") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(IslandButtonStyle())
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
