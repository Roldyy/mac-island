import IslandUI
import SwiftUI

/// The body of the "Scanner IP" Settings page: the scanner itself, then its real preferences.
struct IPScannerSettingsBody: View {
    let model: IPScannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.l) {
            IPScannerPanel(model: model)
            preferences
        }
    }

    private var preferences: some View {
        let settings = model.settings
        return IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Réglages du scan", subtitle: "S’appliquent au prochain scan. Rien n’est enregistré sur les appareils trouvés.")
                IslandRow("Connexions simultanées", subtitle: "De \(ScanConfiguration.concurrencyRange.lowerBound) à \(ScanConfiguration.concurrencyRange.upperBound).", symbol: "square.stack.3d.up") {
                    Stepper(value: Bindable(settings).concurrency, in: ScanConfiguration.concurrencyRange, step: 8) {
                        Text("\(settings.concurrency)").font(.islandValue).foregroundStyle(IslandPalette.textPrimary.color)
                    }
                    .fixedSize()
                    .accessibilityLabel("Connexions simultanées")
                }
                IslandRow("Délai par appareil", subtitle: "Au-delà, l’appareil est considéré muet.", symbol: "timer") {
                    Stepper(value: Bindable(settings).timeoutMs, in: ScanConfiguration.timeoutRangeMs, step: 100) {
                        Text("\(settings.timeoutMs) ms").font(.islandValue).foregroundStyle(IslandPalette.textPrimary.color)
                    }
                    .fixedSize()
                    .accessibilityLabel("Délai par appareil")
                }
                IslandRow("Noms par DNS inverse", symbol: "textformat") {
                    Toggle(isOn: Bindable(settings).resolveNames) { EmptyView() }
                        .toggleStyle(IslandToggleStyle()).fixedSize().accessibilityLabel("Noms par DNS inverse")
                }
                IslandRow("Noms Bonjour", subtitle: "Écoute quelques secondes les services annoncés (AirPlay, imprimantes...).", symbol: "bonjour") {
                    Toggle(isOn: Bindable(settings).useBonjour) { EmptyView() }
                        .toggleStyle(IslandToggleStyle()).fixedSize().accessibilityLabel("Noms Bonjour")
                }
                IslandHeader("Ports du scan de ports", subtitle: PortPreset.notice)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: IslandSpacing.xs) {
                    ForEach(PortPreset.all) { preset in
                        Toggle(isOn: Binding(
                            get: { settings.ports.contains(preset.port) },
                            set: { on in
                                if on { settings.ports.insert(preset.port) } else { settings.ports.remove(preset.port) }
                            })) {
                            Text("\(preset.port) \(preset.service)").font(.islandCaption).foregroundStyle(IslandPalette.textPrimary.color)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                Button("Rétablir les valeurs par défaut") { settings.resetToDefaults() }.buttonStyle(IslandButtonStyle())
            }
        }
    }
}
