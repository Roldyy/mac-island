import SwiftUI

/// The "Écran" tab: brightness on top, auto-quit below. Black island UI, no keyboard grab.
struct DisplayView: View {
    let brightness: BrightnessModel
    let autoQuit: AutoQuitModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BrightnessSection(model: brightness)
                Divider().overlay(.white.opacity(0.15))
                AutoQuitSection(model: autoQuit)
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(.white)
        .onAppear {
            brightness.refresh()
            autoQuit.tick()
        }
    }
}
