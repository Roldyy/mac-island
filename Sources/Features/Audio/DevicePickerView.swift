import SwiftUI

/// Default device for one direction. Shows only devices that support it.
struct DevicePickerView: View {
    let title: String
    let direction: AudioDirection
    let model: AudioFeatureModel

    var body: some View {
        let current = direction == .output ? model.defaultOutput : model.defaultInput
        let choices = model.devices.filter { $0.supports(direction) }
        HStack {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 4)
            Menu(choices.first { $0.uid == current }?.name ?? "Aucun") {
                ForEach(choices) { device in
                    Button(device.name) { model.setDefault(uid: device.uid, direction: direction) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Appareil par défaut, \(title)")
        }
    }
}
