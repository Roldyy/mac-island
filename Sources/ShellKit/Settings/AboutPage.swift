import AppKit
import IslandUI
import SwiftUI

/// "À propos": version, licence and links.
struct AboutPage: View {
    let page: SettingsPage

    static func version(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "développement"
    }

    var body: some View {
        SettingsPageScaffold(page: page) {
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.m) {
                        Image(systemName: "rectangle.topthird.inset.filled")
                            .font(.system(size: 34)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                            Text("Mac Island").font(.system(size: 17, weight: .semibold))
                            Text("Version \(Self.version())").font(.islandCaption)
                                .foregroundStyle(IslandPalette.textSecondary.color)
                        }
                    }
                    Text("Une île sous l’encoche qui réunit vos outils du quotidien : agents, presse-papiers, étagère, mixeur, moniteur.")
                        .font(.islandBody).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    link("Voir le projet sur GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com/Roldyy/mac-island")
                    link("Lire la licence (MIT)", "doc.text", "https://github.com/Roldyy/mac-island/blob/main/LICENSE")
                    link("Signaler un problème", "exclamationmark.bubble", "https://github.com/Roldyy/mac-island/issues")
                    Divider()
                    Text("© 2026 Roldy Management. Logiciel libre sous licence MIT.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
    }

    private func link(_ title: String, _ symbol: String, _ url: String) -> some View {
        Button(title, systemImage: symbol) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
        .buttonStyle(IslandButtonStyle())
    }
}
