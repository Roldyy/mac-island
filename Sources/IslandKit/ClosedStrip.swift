import SwiftUI

/// The closed island, redrawn whenever the ambient center publishes new content. The sizes come from the
/// environment, so the view holds no reference to the island. While it is on screen the center may rotate.
/// It lives here (not in the app target) so the tests host the very view the app draws.
public struct ClosedStrip: View {
    @EnvironmentObject private var state: IslandState
    @ObservedObject private var ambient: AmbientCenter

    public init(ambient: AmbientCenter) { self.ambient = ambient }

    public var body: some View {
        AmbientStrip(
            content: ambient.content, notchWidth: state.notchWidth, isNotched: ambient.isNotched,
            size: CGSize(width: state.closedWidth, height: state.closedHeight))
            .onAppear { ambient.setVisible(true) }
            .onDisappear { ambient.setVisible(false) }
    }
}
