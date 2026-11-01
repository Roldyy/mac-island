import IslandUI
import SwiftUI

/// One device: a summary line, and on click its details and actions (copy, open, port scan).
struct DeviceRowView: View {
    let model: IPScannerModel
    let record: DeviceRecord

    private var isSelected: Bool { model.selectedHost == record.ip }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            Button { model.selectedHost = isSelected ? nil : record.ip } label: { summary }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityText)
                .accessibilityHint(isSelected ? "Masque les détails" : "Affiche les détails")
            if isSelected { details }
        }
    }

    private var summary: some View {
        HStack(spacing: IslandSpacing.s) {
            VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                HStack(spacing: IslandSpacing.xs) {
                    Text(record.ip.description).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                    if record.isGateway { IslandBadge("Passerelle", status: .info) }
                    if record.isThisMac { IslandBadge("Ce Mac", status: .neutral) }
                }
                Text(record.displayName ?? "Nom inconnu").font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
                Text([record.mac?.description, record.vendor].compactMap { $0 }.joined(separator: " · "))
                    .font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color).lineLimit(1)
            }
            Spacer(minLength: IslandSpacing.s)
            VStack(alignment: .trailing, spacing: IslandSpacing.xxs) {
                if let ms = record.latencyMs { Text(String(format: "%.0f ms", ms)).font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color) }
                if !record.openPorts.isEmpty {
                    Text(record.openPorts.map(String.init).joined(separator: " ")).font(.islandFootnote).foregroundStyle(IslandPalette.statusSuccess.color)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        var parts = [record.ip.description, record.displayName ?? "nom inconnu"]
        if let vendor = record.vendor { parts.append(vendor) }
        if let ms = record.latencyMs { parts.append(String(format: "%.0f millisecondes", ms)) }
        if !record.openPorts.isEmpty { parts.append("ports ouverts " + record.openPorts.map(String.init).joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var details: some View {
        HStack(spacing: IslandSpacing.s) {
            Button("Copier l’IP") { model.copyIP(record) }.buttonStyle(IslandButtonStyle())
            if record.mac != nil { Button("Copier la MAC") { model.copyMAC(record) }.buttonStyle(IslandButtonStyle()) }
            ForEach(record.openPorts.filter { PortPreset.browserURL(host: record.ip, port: $0) != nil }, id: \.self) { port in
                Button("Ouvrir :\(port)") { model.openInBrowser(record, port: port) }.buttonStyle(IslandButtonStyle())
            }
        }
        Text(PortPreset.notice).font(.islandCaption).foregroundStyle(IslandPalette.statusWarning.color)
        HStack(spacing: IslandSpacing.s) {
            if case .scanning(let host, let done, let total) = model.portScanState, host == record.ip {
                Button("Arrêter") { model.cancelPortScan() }.buttonStyle(IslandButtonStyle(.destructive))
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(maxWidth: 120)
            } else {
                Button("Scanner les ports") { model.scanPorts(of: record.ip) }
                    .buttonStyle(IslandButtonStyle())
                    .disabled(model.portScanState.isScanning)
            }
        }
        portResult
    }

    @ViewBuilder private var portResult: some View {
        switch model.portScanState {
        case .finished(let host, let open) where host == record.ip:
            Text(open.isEmpty ? "Aucun port ouvert parmi la liste." :
                    "Ouverts : " + open.map { port in PortPreset.service(for: port).map { "\(port) (\($0))" } ?? "\(port)" }.joined(separator: ", "))
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        case .failed(let message):
            Text(message).font(.islandCaption).foregroundStyle(IslandPalette.statusDanger.color)
        default:
            EmptyView()
        }
    }
}
