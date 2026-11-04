import SwiftUI

/// The terminal plus a thin toolbar. The toolbar never takes the keyboard: clicking the button
/// leaves focus where it was.
struct TerminalTabView: View {
    /// A program is running in front of the shell: the first click asks, the second (within 3 s) resets.
    @State private var confirmingProgram: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Button {
                    reset()
                } label: {
                    Label(confirmingProgram.map { "Quitter \($0) ?" } ?? "Réinitialiser",
                          systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(confirmingProgram == nil ? 0.10 : 0.22), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.75))
                .help("Ferme ce terminal et en ouvre un neuf, propre, dans votre dossier personnel")
                .accessibilityLabel("Réinitialiser le terminal")
                Button {
                    TerminalSession.shared.clear()
                } label: {
                    Label("Nettoyer", systemImage: "eraser")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.75))
                .help("Efface l'écran et l'historique du terminal")
                .accessibilityLabel("Nettoyer le terminal")
            }
            TerminalHostView()
        }
    }

    private func reset() {
        let session = TerminalSession.shared
        if confirmingProgram == nil, case .confirm(let process) = session.resetDecision() {
            confirmingProgram = process
            Task {
                try? await Task.sleep(for: .seconds(3))
                confirmingProgram = nil
            }
            return
        }
        confirmingProgram = nil
        session.resetToFresh()
    }
}
