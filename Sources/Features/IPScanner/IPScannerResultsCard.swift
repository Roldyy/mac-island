import IslandKit
import IslandUI
import SwiftUI

/// The results: search, sort, filter, one row per device, CSV export.
struct IPScannerResultsCard: View {
    let model: IPScannerModel
    @Environment(\.islandActions) private var island

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Appareils", subtitle: model.devices.isEmpty ? nil : "\(model.visibleDevices.count) sur \(model.devices.count). Les résultats ne sont pas conservés.")
                if model.devices.isEmpty {
                    IslandEmptyState(symbol: "dot.radiowaves.left.and.right", message: "Aucun résultat. Lancez un scan pour lister les appareils.")
                } else {
                    controls
                    LazyVStack(alignment: .leading, spacing: IslandSpacing.s) {
                        ForEach(model.visibleDevices) { DeviceRowView(model: model, record: $0) }
                    }
                    HStack(spacing: IslandSpacing.s) {
                        Button("Copier le CSV") { model.copyCSV() }.buttonStyle(IslandButtonStyle())
                        Button("Enregistrer le CSV") { model.saveCSV() }.buttonStyle(IslandButtonStyle())
                    }
                    Text("Le fabricant vient d’une petite table intégrée : il est indicatif.")
                        .font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            TextField("Rechercher (IP, nom, MAC, fabricant, port)", text: Bindable(model).search)
                .textFieldStyle(.roundedBorder)
                .font(.islandBody)
                .simultaneousGesture(TapGesture().onEnded { island.focusKeyboard() })
                .accessibilityLabel("Rechercher dans les résultats")
            HStack(spacing: IslandSpacing.s) {
                Picker("Tri", selection: Bindable(model).sort) {
                    ForEach(ResultSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Filtre", selection: Bindable(model).filter) {
                    ForEach(ResultFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
