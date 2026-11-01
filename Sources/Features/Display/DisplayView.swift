import SwiftUI

/// The "Écran" tab: auto-quit of idle apps. Black island UI, no keyboard grab. Brightness moved to the ported
/// brightness feature and its Settings pages.
struct DisplayView: View {
    let autoQuit: AutoQuitModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AutoQuitSection(model: autoQuit)
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(.white)
        .onAppear { autoQuit.tick() }
    }
}
