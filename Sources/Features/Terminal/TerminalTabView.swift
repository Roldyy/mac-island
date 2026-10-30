import SwiftUI

/// The terminal plus a thin toolbar. The toolbar never takes the keyboard: clicking the button
/// leaves focus where it was.
struct TerminalTabView: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
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
}
