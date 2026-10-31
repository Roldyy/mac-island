import SwiftUI

/// Solid black behind the hardware notch, whatever the content draws on top: the notch has no
/// pixels, and a translucent or empty strip there would show the wallpaper around it.
struct NotchBackdrop<Content: View>: View {
    @EnvironmentObject private var state: IslandState
    let content: Content

    var body: some View {
        content.background(alignment: .top) {
            // IslandSurface.notchBlack once IslandUI provides it.
            Color.black.frame(width: state.notchWidth, height: state.notchHeight)
        }
    }
}
