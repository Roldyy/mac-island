import AppKit
import IslandUI
import SwiftUI

/// "Soutenir": a Roldy Management contact card (website link) and the GitHub star, each one a real link.
/// The GPL credit to Vorssaint lives in About and Nouveautés as attribution text only.
struct SupportPage: View {
    let page: SettingsPage

    static let starURL = "https://github.com/Roldyy/mac-island"

    var body: some View {
        SettingsPageScaffold(page: page) {
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.m) {
                    HStack(spacing: IslandSpacing.s) {
                        Image(systemName: "envelope.fill").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                        Text("Contacter Roldy Management").font(.islandBodyEmphasis)
                    }
                    Text("Mac Island reste gratuit et local, sans publicité ni suivi d’utilisation. Une question, une idée ou un besoin sur mesure : écrivez-nous depuis le site de Roldy Management.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    RoldyCreditCard()
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
