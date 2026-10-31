import AppKit
import IslandUI
import SwiftUI

/// "Soutenir": a thank-you and the project link.
struct SupportPage: View {
    let page: SettingsPage

    var body: some View {
        SettingsPageScaffold(page: page) {
            IslandCard {
                VStack(alignment: .leading, spacing: IslandSpacing.m) {
                    Text("Merci d’utiliser Mac Island.").font(.islandBodyEmphasis)
                    Text("Le projet est libre et gratuit. Une étoile sur GitHub aide d’autres personnes à le trouver.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    Button("Ajouter une étoile sur GitHub", systemImage: "star") {
                        if let url = URL(string: "https://github.com/Roldyy/mac-island") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(IslandButtonStyle(.prominent))
                }
            }
        }
    }
}
