import IslandKit
import SwiftUI

struct ScratchpadPane: View {
    @Bindable var model: ClipboardModel
    @Environment(\.islandActions) private var actions

    var body: some View {
        if model.scratchpadReadOnly {
            // One writer for Scratchpad.json: the ported Scratchpad (Settings, "Brouillon") owns it while it runs.
            Text("Le bloc-notes est géré par la fonction Brouillon : ouvrez-le avec son raccourci ou depuis les réglages.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Bloc-notes géré par la fonction Brouillon")
        } else {
            editor
        }
    }

    private var editor: some View {
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
        // The ported Scratchpad may have rewritten the file while this pane was hidden.
        .onAppear { model.reloadScratchpadIfChanged() }
    }
}
