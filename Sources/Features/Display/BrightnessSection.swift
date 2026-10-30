import SwiftUI

/// Built-in display brightness. External displays (DDC) are not supported.
struct BrightnessSection: View {
    @Bindable var model: BrightnessModel

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(model.level) }, set: { model.setLevel(Float($0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Luminosité", isOn: $model.controlEnabled)
                .toggleStyle(.switch)
                .font(.headline)
                .accessibilityLabel("Contrôle de la luminosité")
            if model.controlEnabled {
                if model.isAvailable {
                    HStack(spacing: 8) {
                        Button("Moins lumineux", systemImage: "sun.min") { model.nudge(.down) }
                            .labelStyle(.iconOnly)
                        Slider(value: sliderValue, in: 0...1)
                            .accessibilityLabel("Luminosité de l'écran intégré")
                            .accessibilityValue(Text(model.level, format: .percent.precision(.fractionLength(0))))
                        Button("Plus lumineux", systemImage: "sun.max") { model.nudge(.up) }
                            .labelStyle(.iconOnly)
                        Button("Rétablir", systemImage: "arrow.uturn.backward") { model.restoreInitial() }
                            .labelStyle(.iconOnly)
                            .help("Revenir au niveau d'ouverture")
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Luminosité indisponible sur cet écran.")
                        .foregroundStyle(.secondary)
                }
                Text("Écran intégré uniquement. Les écrans externes (DDC) ne sont pas gérés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
