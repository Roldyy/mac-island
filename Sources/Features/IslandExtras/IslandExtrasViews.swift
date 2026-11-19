import AppKit
import IslandKit
import IslandUI
import ShellKit
import SwiftUI

private struct ExtrasBackdrop: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(IslandPalette.textPrimary.color)
            .background(.black)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Notes

struct NotesTabView: View {
    @Bindable var model: NotesModel

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            TextEditor(text: $model.text)
                .font(.islandBody)
                .scrollContentBackground(.hidden)
                .padding(IslandSpacing.s)
                .background(IslandPalette.textPrimary.color.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
                .accessibilityLabel("Notes")
            HStack {
                Text(model.saveFailed ? "Enregistrement impossible" : "Enregistré sur ce Mac, jamais envoyé")
                    .foregroundStyle(model.saveFailed ? IslandPalette.status(.danger).color : IslandPalette.textSecondary.color)
                Spacer()
                Text("\(model.remaining) caractères restants").monospacedDigit()
                    .foregroundStyle(IslandPalette.textTertiary.color)
            }
            .font(.islandFootnote)
        }
        .padding(IslandSpacing.m)
        .modifier(ExtrasBackdrop())
    }
}

// MARK: - Couleurs

struct ColoursTabView: View {
    let model: ColoursModel

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.m) {
            HStack {
                Button { model.pick() } label: { Label("Prélever une couleur", systemImage: "eyedropper") }
                    .buttonStyle(IslandButtonStyle(.prominent))
                    .disabled(model.isPicking)
                    .help("Ouvre la loupe du système : cliquez sur un pixel de l’écran.")
                Spacer()
                if !model.recent.hexes.isEmpty {
                    Button("Effacer") { model.clear() }
                        .buttonStyle(IslandButtonStyle())
                        .help("Oublie les couleurs récentes.")
                }
            }
            if model.recent.hexes.isEmpty {
                IslandEmptyState(symbol: "eyedropper", message: "Aucune couleur prélevée pour l’instant.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: IslandSpacing.s)], spacing: IslandSpacing.s) {
                        ForEach(model.recent.hexes, id: \.self) { hex in
                            Button { model.copyHex(hex) } label: {
                                HStack(spacing: IslandSpacing.s) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Self.color(hex))
                                        .frame(width: 22, height: 22)
                                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(IslandPalette.separator.color, lineWidth: 0.5))
                                    Text(model.lastCopied == hex ? "Copié" : hex).font(.islandValue)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(IslandButtonStyle())
                            .help("Copie \(hex) dans le presse-papiers.")
                            .accessibilityLabel("Couleur \(hex), copier")
                        }
                    }
                }
            }
        }
        .padding(IslandSpacing.m)
        .modifier(ExtrasBackdrop())
    }

    static func color(_ hex: String) -> Color {
        guard let value = RecentColours.normalised(hex), let rgb = UInt32(value.dropFirst(), radix: 16) else { return .gray }
        return Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
}

// MARK: - Batterie

struct BatteryTabView: View {
    var body: some View {
        // One cheap IOKit read every 30 s while the tab is on screen; nothing runs while it is not.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            content(reading: BatteryReading.current(), health: BatteryHealth.current())
        }
        .padding(IslandSpacing.m)
        .modifier(ExtrasBackdrop())
    }

    @ViewBuilder
    private func content(reading: BatteryReading?, health: BatteryHealth?) -> some View {
        if let reading {
            let display = BatteryDisplay(reading: reading, health: health)
            IslandCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.m) {
                        Image(systemName: reading.symbol).font(.system(size: 30))
                            .foregroundStyle(IslandPalette.status(reading.status).color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                            Text(display.percentText).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                            Text(display.stateText).font(.islandBody).foregroundStyle(IslandPalette.textSecondary.color)
                        }
                    }
                    if let remaining = display.remainingText { Text(remaining).font(.islandBody) }
                    if let healthText = display.healthText {
                        Text(healthText).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(reading.spoken)
        } else {
            IslandEmptyState(symbol: "powerplug", message: "Ce Mac n’a pas de batterie.")
        }
    }
}
