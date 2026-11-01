import FanShared
import SwiftUI

/// Manual control, visually separated from monitoring. The sliders and the return button are
/// disabled unless the helper is approved and reachable; the install and approval buttons stay
/// usable because they are how the user gets there.
struct ManualControlSection: View {
    /// Manual mode survives closing the island: it ends on the button, on quit, or when hot.
    static let warning = """
        Forcer les ventilateurs court-circuite la régulation de macOS. Ils restent forcés jusqu'à \
        « Retour automatique », jusqu'à ce que l'app quitte ou que le Mac chauffe (au-delà de 95 °C).
        """

    /// Shown instead of the sliders while a curve or a preset from the Ventilos settings drives the fans.
    static let externalNote = """
        Une courbe ou un réglage des Réglages > Ventilos pilote actuellement les ventilateurs. Les curseurs sont \
        verrouillés pour éviter deux commandes à la fois.
        """
    static let takeBackTitle = "Reprendre la main"

    let model: FansModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contrôle manuel")
                .font(.headline)
                .foregroundStyle(.white)

            HelperStatusRow(model: model)

            Label(Self.warning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
                .fixedSize(horizontal: false, vertical: true)

            if let control = model.externalControl {
                // The ported curve or preset holds the fans: one controller at a time.
                Text(Self.externalNote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    control.takeBack()
                } label: {
                    Label(Self.takeBackTitle, systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .accessibilityHint("Arrête la courbe et rend le contrôle des ventilateurs à macOS")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.readings) { reading in
                        if let range = model.range(for: reading.index) {
                            FanSliderRow(model: model, fan: reading.index, range: range)
                        }
                    }
                }
                .disabled(!model.manualAvailable)
                .opacity(model.manualAvailable ? 1 : 0.4)

                Button {
                    Task { await model.returnToAutomatic() }
                } label: {
                    Label("Retour automatique", systemImage: "arrow.uturn.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(!model.helperReachable)
                .accessibilityHint("Rend le contrôle des ventilateurs à macOS")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.35)))
    }
}

/// The slider edits a local value; the model only sees it when the drag ends, so one gesture is
/// one helper request (the helper rate-limits anyway).
struct FanSliderRow: View {
    let model: FansModel
    let fan: Int
    let range: ClosedRange<Double>
    @State private var value = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Ventilateur \(fan + 1)")
                    .font(.caption)
                    .foregroundStyle(.white)
                Spacer()
                Text(FanFormat.rpm(value))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
            Slider(value: $value, in: range) { editing in
                guard !editing else { return }
                model.targets[fan] = value
                Task { await model.commitTarget(fan: fan) }
            }
            .accessibilityLabel("Vitesse cible du ventilateur \(fan + 1)")
            .accessibilityValue(FanFormat.spoken(value))
        }
        .onAppear { value = model.targets[fan] ?? range.lowerBound }
        .onChange(of: model.targets[fan]) { _, newValue in
            if let newValue { value = newValue }
        }
    }
}

struct HelperStatusRow: View {
    let model: FansModel

    var body: some View {
        switch model.installStatus {
        case .notRegistered:
            HStack {
                Text("Helper non installé. L'installation demande ensuite votre accord d'administrateur.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Installer le helper") { model.installHelper() }
                    .controlSize(.small)
            }
        case .requiresApproval:
            HStack {
                Text("En attente de votre accord : Réglages Système > Général > Ouverture.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Ouvrir les Réglages") { model.openLoginItems() }
                    .controlSize(.small)
            }
        case .enabled:
            Label(model.helperReachable ? "Helper prêt." : "Helper approuvé mais injoignable.",
                  systemImage: model.helperReachable ? "checkmark.shield" : "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(model.helperReachable ? Color.green : Color.orange)
        case .notFound:
            Label("Helper absent de cette version de l'app : contrôle manuel indisponible.",
                  systemImage: "xmark.shield")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
