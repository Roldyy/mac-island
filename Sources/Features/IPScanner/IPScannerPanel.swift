import IslandUI
import SwiftUI

/// The whole scanner, shared by the island tab and the Settings page.
struct IPScannerPanel: View {
    let model: IPScannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.m) {
            if model.isActive {
                IPScannerNetworkCard(model: model)
                IPScannerScanCard(model: model)
                IPScannerResultsCard(model: model)
            } else {
                IslandEmptyState(symbol: "network", message: "Le scanner IP est désactivé. Activez-le dans Réglages, Fonctions.")
            }
        }
        .onAppear { model.refreshInterfaces() }
    }
}

/// The island's "Réseau local" tab.
struct IPScannerTabView: View {
    let model: IPScannerModel

    var body: some View {
        ScrollView {
            IPScannerPanel(model: model)
                .padding(IslandSpacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(IslandPalette.textPrimary.color)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }
}
