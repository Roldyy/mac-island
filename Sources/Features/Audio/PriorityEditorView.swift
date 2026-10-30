import SwiftUI

/// Ordered priority list for output or input. Drag a row to reorder; top row wins.
struct PriorityEditorView: View {
    let model: AudioFeatureModel
    @State private var direction: AudioDirection = .output

    var body: some View {
        let uids = model.priority.priority(for: direction)
        let names = model.deviceNames()
        let available = Set(model.devices.filter { $0.supports(direction) }.map(\.uid))
        VStack(alignment: .leading, spacing: 6) {
            Picker("Liste", selection: $direction) {
                Text("Sortie").tag(AudioDirection.output)
                Text("Entrée").tag(AudioDirection.input)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Liste de priorité")

            List {
                ForEach(uids, id: \.self) { uid in
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.white.opacity(0.35))
                            .accessibilityHidden(true)
                        Circle().fill(available.contains(uid) ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(label(uid, names: names))
                            .font(.caption)
                            .foregroundStyle(available.contains(uid) ? .white : .white.opacity(0.5))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Retirer \(label(uid, names: names)) de la liste", systemImage: "minus.circle") {
                            model.priority.setPriority(uids.filter { $0 != uid }, for: direction)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Glisser pour changer la priorité")
                }
                .onMove { source, destination in
                    var next = uids
                    next.move(fromOffsets: source, toOffset: destination)
                    model.priority.setPriority(next, for: direction)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60, maxHeight: 130)

            let addable = model.devices.filter { $0.supports(direction) && !uids.contains($0.uid) }
            if !addable.isEmpty {
                Menu("Ajouter un appareil", systemImage: "plus") {
                    ForEach(addable) { device in
                        Button(device.name) {
                            model.priority.setPriority(uids + [device.uid], for: direction)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func label(_ uid: String, names: [String: String]) -> String {
        model.devices.first { $0.uid == uid }?.name ?? names[uid] ?? "Appareil absent"
    }
}
