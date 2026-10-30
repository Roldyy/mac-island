import IslandKit
import SwiftUI

/// The Mixer tab. Black island, no keyboard capture, no hover side effects.
struct AudioView: View {
    let model: AudioFeatureModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if model.mixer.apps.isEmpty {
                    Text("Aucune app ne joue du son.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.mixer.apps) { app in
                                MixerRowView(app: app, mixer: model.mixer)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                permissionLine
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                DevicePickerView(title: "Sortie", direction: .output, model: model)
                DevicePickerView(title: "Entrée", direction: .input, model: model)
                Divider().overlay(.white.opacity(0.15))
                PriorityEditorView(model: model)
            }
            .frame(width: 230, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
    }

    private var permissionLine: some View {
        HStack(spacing: 8) {
            Text(model.permission.line)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
                .accessibilityLabel(model.permission.line)
            if model.permission.canRequest {
                Button("Autoriser la capture audio") { model.requestPermission() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Demande l'autorisation de capture audio au système")
            }
        }
    }
}
