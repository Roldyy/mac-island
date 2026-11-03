import IslandUI
import SwiftUI

/// The whole feature, shared by the island tab and the Settings page.
struct DefaultAppsPanel: View {
    let model: DefaultAppsModel

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.m) {
            if model.isActive {
                DefaultAppsSourceCard(model: model)
                if model.source != nil {
                    DefaultAppsReplacementCard(model: model)
                }
                if let preview = model.preview {
                    DefaultAppsPreviewCard(model: model, preview: preview)
                }
                if let report = model.report {
                    DefaultAppsResultCard(model: model, report: report)
                }
                DefaultAppsSchemeCard(model: model)
                DefaultAppsHistoryCard(model: model)
                DefaultAppsGuardCard(model: model)
            } else {
                IslandEmptyState(symbol: "app.badge.checkmark",
                                 message: "Les applications par défaut sont désactivées. Activez-les dans Réglages, Fonctions.")
            }
        }
        .task(id: model.isActive) {
            if model.isActive && model.phase == .idle { await model.refresh() }
        }
    }
}

/// The island's "Apps par défaut" tab.
struct DefaultAppsTabView: View {
    let model: DefaultAppsModel

    var body: some View {
        ScrollView {
            DefaultAppsPanel(model: model)
                .padding(IslandSpacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(IslandPalette.textPrimary.color)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }
}
