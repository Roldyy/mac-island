import IslandUI
import SwiftUI

/// Interface, address, mask, gateway, the opt-in public IP and the Local Network permission.
struct IPScannerNetworkCard: View {
    let model: IPScannerModel

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Réseau local", subtitle: "Lecture seule : aucune requête n’est envoyée pour afficher ces informations.")
                if model.interfaces.isEmpty {
                    IslandEmptyState(symbol: "network.slash", message: "Aucune interface réseau active.")
                } else {
                    if model.interfaces.count > 1 { interfacePicker }
                    if let interface = model.selectedInterface { details(interface) }
                }
                publicIPRow
                accessRow
            }
        }
    }

    private var interfacePicker: some View {
        Picker("Interface", selection: Bindable(model).selectedInterfaceID) {
            ForEach(model.interfaces) { Text("\($0.name) · \($0.address.description)").tag(Optional($0.id)) }
        }
        .pickerStyle(.menu)
        .disabled(model.scanState.isScanning)
        .accessibilityLabel("Interface réseau")
    }

    @ViewBuilder private func details(_ interface: LocalInterface) -> some View {
        row("Adresse IPv4", interface.address.description, symbol: "number")
        row("Masque", "\(interface.netmask.description) (/\(interface.subnet.prefix))", symbol: "square.split.2x2")
        row("Passerelle", interface.gateway?.description ?? "inconnue", symbol: "arrow.triangle.branch")
        row("Plage", interface.subnet.description, symbol: "point.3.connected.trianglepath.dotted")
        if !interface.isScannable {
            IslandBadge("Réseau non local : le scan est refusé", status: .warning)
        }
    }

    private func row(_ title: String, _ value: String, symbol: String) -> some View {
        IslandRow(title, symbol: symbol) {
            Text(value).font(.islandValue).foregroundStyle(IslandPalette.textPrimary.color).textSelection(.enabled)
        }
    }

    @ViewBuilder private var publicIPRow: some View {
        let host = PublicIPLookup.url.host ?? ""
        IslandRow("Adresse publique", subtitle: "Jamais récupérée seule. Un clic envoie une requête à \(host).", symbol: "globe") {
            switch model.publicIP {
            case .notFetched:
                Button("Afficher") { model.fetchPublicIP() }.buttonStyle(IslandButtonStyle())
            case .fetching:
                ProgressView().controlSize(.small)
            case .value(let text):
                Text(text).font(.islandValue).foregroundStyle(IslandPalette.textPrimary.color).textSelection(.enabled)
            case .failed:
                Button("Réessayer") { model.fetchPublicIP() }.buttonStyle(IslandButtonStyle())
            }
        }
        if model.publicIP == .failed {
            Text("Adresse publique indisponible.").font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }

    @ViewBuilder private var accessRow: some View {
        IslandRow("Accès au réseau local", subtitle: "macOS le demande à la première connexion locale.", symbol: "lock.shield",
                  status: model.localNetwork == .granted ? .success : (model.localNetwork == .denied ? .danger : nil)) {
            Button(model.localNetwork == .granted ? "Revérifier" : "Autoriser") { model.requestLocalNetworkAccess() }
                .buttonStyle(IslandButtonStyle())
                .disabled(model.checkingLocalNetwork)
        }
        if model.localNetwork == .denied {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                Text("macOS a refusé l’accès au réseau local : le scan ne trouvera rien. Autorisez Mac Island dans Réglages Système, Confidentialité et sécurité, Réseau local.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                Button("Ouvrir Réseau local") { model.openLocalNetworkPane() }.buttonStyle(IslandButtonStyle())
            }
        }
    }
}
