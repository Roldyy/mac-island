import IslandKit
import SwiftUI

struct ScratchpadPane: View {
    @Bindable var model: ClipboardModel
    @Environment(\.islandActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(model.pads) { pad in
                            Button(pad.name) { model.selectPad(pad.id) }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(.white)
                                .background(Color.white.opacity(pad.id == model.selectedPadID ? 0.25 : 0.08),
                                            in: Capsule())
                                .accessibilityLabel("Note \(pad.name)")
                                .accessibilityAddTraits(pad.id == model.selectedPadID ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Button("Nouvelle note", systemImage: "plus") { model.addPad() }
                    .labelStyle(.iconOnly)
                Button("Supprimer la note", systemImage: "trash") { model.removeSelectedPad() }
                    .labelStyle(.iconOnly)
                    .disabled(model.pads.count <= 1)
            }
            TextEditor(text: $model.padText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                // Take the keyboard on click only.
                .simultaneousGesture(TapGesture().onEnded { actions.focusKeyboard() })
                .accessibilityLabel("Texte de la note")
        }
    }
}
