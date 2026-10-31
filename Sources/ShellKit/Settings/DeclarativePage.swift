import IslandKit
import IslandUI
import SwiftUI

/// A page built from the rows noted on the reference page: real controls where a preference exists,
/// greyed "Bientôt" rows elsewhere.
struct DeclarativePage: View {
    let page: SettingsPage
    let registry: FeatureRegistry
    let store: LiveStore
    let openPermission: @MainActor (FeaturePermission) -> Void

    var body: some View {
        SettingsPageScaffold(page: page) {
            ForEach(featureIDs, id: \.self) { FeatureStatusCard(registry: registry, featureID: $0, openPermission: openPermission) }
            ForEach(SettingsPageModel.blocks(for: page)) { block in
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    if !block.title.isEmpty { IslandHeader(block.title) }
                    IslandCard {
                        VStack(alignment: .leading, spacing: IslandSpacing.s) {
                            ForEach(block.rows) { row in
                                view(for: row)
                            }
                        }
                    }
                }
            }
            if SettingsPageModel.blocks(for: page).isEmpty && featureIDs.isEmpty {
                IslandEmptyState(symbol: "hourglass", message: "Cette page arrive bientôt.")
            }
        }
    }

    private var featureIDs: [String] {
        var ids: [String] = []
        if let own = page.featureID { ids.append(own) }
        ids += SettingsLive.controls(for: page.id)?.featureIDs ?? []
        return ids
    }

    @ViewBuilder private func view(for row: SettingsRow) -> some View {
        switch row.item.kind {
        case .caption:
            Text(row.item.label).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        case .heading:
            IslandHeader(row.item.label)
        default:
            if let control = row.control {
                LiveControlView(label: row.item.label, hint: control.hint, control: control, store: store)
            } else {
                PlannedRowView(item: row.item)
            }
        }
    }
}
