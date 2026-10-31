import IslandUI
import SwiftUI

/// A card of the Settings window: a flat fill and a hairline, no material. Each `IslandCard` put a
/// blur view (and an accessibility observer) behind every card, several per page, on top of a window
/// that is already translucent; that was the main cost of opening a page. Increase Contrast gets a
/// stronger hairline.
struct SettingsCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
        content
            .padding(IslandSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(IslandPalette.separator.color, lineWidth: contrast == .increased ? 1.5 : 0.5) }
    }
}
