import SwiftUI

/// One audio app: icon, name, mute, slider. The slider is a position; the curve is applied in the model.
struct MixerRowView: View {
    let app: MixerApp
    let mixer: MixerModel
    @State private var value: Double

    init(app: MixerApp, mixer: MixerModel) {
        self.app = app
        self.mixer = mixer
        _value = State(initialValue: app.position)
    }

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(bundleID: app.id, pid: app.pid)
            Text(app.name)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            Slider(value: $value, in: 0...1)
                .disabled(app.isMuted)
                .accessibilityLabel("Volume de \(app.name)")
                .accessibilityValue("\(Int((value * 100).rounded())) pour cent")
            Button(app.isMuted ? "Réactiver le son de \(app.name)" : "Couper le son de \(app.name)",
                   systemImage: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                mixer.setMuted(!app.isMuted, for: app.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(app.isMuted ? Color.orange : .white.opacity(0.8))
            .help(app.isMuted ? "Réactiver le son" : "Couper le son")
        }
        .onChange(of: value) { _, new in mixer.setPosition(new, for: app.id) }
        .onChange(of: app.position) { _, new in if new != value { value = new } }
    }
}
