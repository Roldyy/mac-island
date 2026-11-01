import AppKit
import IslandUI
import SwiftUI

/// "Soutenir": the two ways to say thank you, each one a real link.
///
/// Mac Island is a GPL port of Vorssaint. It has no donation page of its own: the only place money can go is the
/// original author's Buy Me a Coffee, and the page says so rather than hide it.
struct SupportPage: View {
    let page: SettingsPage

    static let coffeeURL = "https://buymeacoffee.com/vorssaint"
    static let starURL = "https://github.com/Roldyy/mac-island"

    var body: some View {
        SettingsPageScaffold(page: page) {
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.m) {
                    HStack(spacing: IslandSpacing.s) {
                        Image(systemName: "heart.fill").foregroundStyle(.pink).accessibilityHidden(true)
                        Text("Aidez Mac Island à continuer de grandir").font(.islandBodyEmphasis)
                    }
                    Text("Mac Island reste gratuit et local, sans publicité ni suivi d’utilisation. Il dérive de Vorssaint, et son seul canal de soutien financier est celui de son auteur d’origine : Buy Me a Coffee.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    open("Soutenir Vorssaint sur Buy Me a Coffee", "cup.and.saucer", Self.coffeeURL, prominent: true)
                }
            }
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.m) {
                    HStack(spacing: IslandSpacing.s) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityHidden(true)
                        Text("Une étoile, c’est déjà beaucoup").font(.islandBodyEmphasis)
                    }
                    Text("Un soutien financier n’est jamais attendu. Une étoile sur GitHub aide davantage de personnes à découvrir Mac Island et fait une vraie différence pour son développement.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    open("Ajouter une étoile à Mac Island sur GitHub", "star", Self.starURL, prominent: false)
                }
            }
            Text("Merci d’être là. 🤍").font(.islandBody).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }

    private func open(_ title: String, _ symbol: String, _ url: String, prominent: Bool) -> some View {
        Button(title, systemImage: symbol) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
        .buttonStyle(IslandButtonStyle(prominent ? .prominent : .standard))
    }
}
