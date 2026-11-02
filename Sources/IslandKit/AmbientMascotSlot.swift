import SwiftUI

/// Where the companion is drawn in the closed island. IslandKit cannot see the mascot (it lives in PortKit), so the app
/// registers a factory once at launch; until it does (and in tests) a plain face symbol stands in, so an indicator that
/// the layout kept is never an empty hole in a wing.
public enum AmbientMascotSlot {
    @MainActor public static var make: ((CGFloat) -> AnyView)?

    @MainActor static func view(size: CGFloat) -> some View {
        Group {
            if let make { make(size) } else {
                Image(systemName: "face.smiling")
                    .symbolRenderingMode(.hierarchical)
                    .resizable().scaledToFit()
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
    }
}
