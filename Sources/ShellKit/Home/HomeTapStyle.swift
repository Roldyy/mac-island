import IslandUI
import SwiftUI

/// Pressed feedback for the borderless home controls (round buttons, tiles, transport): a dim, no movement,
/// so Reduce Motion needs nothing special. A disabled control dims further.
struct HomeTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HomeTapBody(configuration: configuration)
    }
}

private struct HomeTapBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}
