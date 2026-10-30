import SwiftUI

enum MonitorSegment: String, CaseIterable, Identifiable {
    case overview = "Aperçu"
    case alerts = "Alertes"
    var id: String { rawValue }
}

/// The tab. Black island, no hover side effect, no keyboard focus taken.
struct MonitorView: View {
    @Bindable var model: MonitorModel
    @State private var segment: MonitorSegment = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let alert = model.currentAlert { AlertBanner(alert: alert, dismiss: model.dismissCurrentAlert) }
            Picker("Section", selection: $segment) {
                ForEach(MonitorSegment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Section du moniteur")

            switch segment {
            case .overview: overview
            case .alerts: AlertSettingsPane(model: model)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .onAppear {
            model.start()
            model.setVisible(true)
        }
        .onDisappear { model.setVisible(false) }
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: 16) {
            UsageRing(title: "Processeur", value: model.cpuPercent, threshold: model.cpuThreshold,
                      history: model.cpuHistory.values)
            UsageRing(title: "Mémoire", value: model.memoryPercent, threshold: model.memoryThreshold,
                      history: model.memoryHistory.values)
            VStack(alignment: .leading, spacing: 8) {
                statusLine
                HStack(alignment: .top, spacing: 12) {
                    ProcessList(title: "Top processeur", rows: model.topByCPU) {
                        "\(Int(($0.cpuPercent ?? 0).rounded())) %"
                    }
                    ProcessList(title: "Top mémoire", rows: model.topByMemory) {
                        $0.residentBytes.formatted(.byteCount(style: .memory))
                    }
                }
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 12) {
            Label(thermalText, systemImage: "thermometer.medium")
            Label(pressureText, systemImage: "memorychip")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("État thermique : \(thermalText). Pression mémoire : \(pressureText).")
    }

    private var thermalText: String {
        switch model.thermal {
        case .nominal: "Thermique normal"
        case .fair: "Thermique tiède"
        case .serious: "Thermique élevé"
        case .critical: "Thermique critique"
        }
    }

    private var pressureText: String {
        switch model.pressure {
        case .normal: "Pression faible"
        case .warning: "Pression moyenne"
        case .critical: "Pression forte"
        case .unknown: "Pression inconnue"
        }
    }
}

private struct AlertBanner: View {
    let alert: AlertNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(alert.title).font(.caption.weight(.semibold))
                Text(alert.message).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button("Fermer", action: dismiss)
                .controlSize(.small)
                .accessibilityLabel("Fermer l'alerte")
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
