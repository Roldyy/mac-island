import IslandKit
import IslandUI
import SwiftUI

/// Range, start and cancel, progress and the large-range confirmation.
struct IPScannerScanCard: View {
    let model: IPScannerModel
    @Environment(\.islandActions) private var island

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Scanner le réseau", subtitle: "Uniquement le sous-réseau de l’interface choisie. Rien ne démarre sans votre clic.")
                TextField("Plage facultative, par exemple 192.168.1.0/28", text: Bindable(model).rangeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.islandBody)
                    .disabled(model.scanState.isScanning)
                    .simultaneousGesture(TapGesture().onEnded { island.focusKeyboard() })
                    .accessibilityLabel("Plage à scanner")
                HStack(spacing: IslandSpacing.s) {
                    if model.scanState.isScanning {
                        Button("Annuler le scan") { model.cancelScan() }.buttonStyle(IslandButtonStyle(.destructive))
                    } else {
                        Button("Lancer le scan") { model.startScan() }
                            .buttonStyle(IslandButtonStyle(.prominent))
                            .disabled(model.selectedInterface == nil || !model.isActive)
                    }
                }
                if let count = model.pendingConfirmation { confirmation(count) }
                status
                if let notice = model.notice, model.pendingConfirmation == nil {
                    Text(notice).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
    }

    private func confirmation(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandBadge("\(count) adresses à parcourir", status: .warning)
            Text("Cette plage dépasse un /22. Le scan reste borné (64 connexions à la fois par défaut) mais il sera long.")
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
            HStack(spacing: IslandSpacing.s) {
                Button("Confirmer le scan") { model.confirmPendingScan() }.buttonStyle(IslandButtonStyle(.prominent))
                Button("Annuler") { model.dismissConfirmation() }.buttonStyle(IslandButtonStyle())
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.scanState {
        case .idle:
            EmptyView()
        case .scanning(let progress):
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                ProgressView(value: progress.fraction)
                Text("\(Self.phaseText(progress.phase)) : \(progress.done) sur \(progress.total), \(progress.found) appareil\(progress.found > 1 ? "s" : "") trouvé\(progress.found > 1 ? "s" : "")")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
            }
        case .finished(let count, let seconds):
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                IslandBadge("\(count) appareil\(count > 1 ? "s" : "") en \(String(format: "%.1f", seconds)) s", status: .success)
                if count <= 1 {
                    Text("Peu de résultats ? Vérifiez l’accès au réseau local ci-dessus : sans lui macOS bloque les connexions locales.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        case .cancelled:
            IslandBadge("Scan annulé", status: .neutral)
        case .failed(let message):
            IslandBadge(message, status: .danger)
        }
    }

    static func phaseText(_ phase: ScanProgress.Phase) -> String {
        switch phase {
        case .probing: "Sondage"
        case .readingTable: "Lecture de la table ARP"
        case .naming: "Recherche des noms"
        }
    }
}
