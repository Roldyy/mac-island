import IslandUI
import SwiftUI

/// One quick tile of the home grid: round glyph, two-line name. A toggle (keep awake) fills when on.
struct HomeTile: View {
    let action: HomeAction
    let context: ShellContext

    var body: some View {
        let available = context.isAvailable(action)
        let on = context.isOn(action)
        Button { context.perform(action) } label: {
            VStack(spacing: IslandSpacing.xs) {
                ZStack {
                    Circle().fill(on ? IslandPalette.accent.color : IslandPalette.textPrimary.color.opacity(0.10))
                    Image(systemName: on ? action.activeSystemImage ?? action.systemImage : action.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(on ? IslandSurface.notchBlack : IslandPalette.textPrimary.color)
                }
                .frame(width: 34, height: 34)
                Text(action.title)
                    .font(.system(size: IslandType.minimumSize, weight: .medium))
                    .foregroundStyle(IslandPalette.textPrimary.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
                    .padding(.horizontal, IslandSpacing.m)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeTapStyle())
        .disabled(!available)
        .help(available ? action.title : "\(action.title) : pas encore disponible")
        .accessibilityLabel(action.title)
        .accessibilityValue(action.activeSystemImage == nil ? "" : (on ? "activé" : "désactivé"))
    }
}
