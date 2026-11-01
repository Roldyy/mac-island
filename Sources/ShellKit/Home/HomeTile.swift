import IslandUI
import SwiftUI

/// One tile of the home grid and of the Explorer: round glyph, two-line name. A toggle (keep awake) fills when on.
/// A switched-off feature is dimmed and a tap opens the Settings, where it can be enabled.
struct HomeTile: View {
    let item: HomeTileItem
    let context: ShellContext

    var body: some View {
        let available = context.isAvailable(item)
        let on = context.isOn(item)
        let action = item.action
        let isClaude = item.isEnabled && action.map(HomeClaude.isClaude) == true
        Button { context.perform(item) } label: {
            VStack(spacing: IslandSpacing.xs) {
                ZStack {
                    Circle().fill(on ? IslandPalette.accent.color : IslandPalette.textPrimary.color.opacity(0.10))
                    Image(systemName: on ? action?.activeSystemImage ?? item.systemImage : item.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(on ? IslandSurface.notchBlack : IslandPalette.textPrimary.color)
                    if isClaude {
                        ClaudeStatusDot().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .offset(x: 3, y: -3)
                    }
                }
                .frame(width: 28, height: 28)
                Text(item.title)
                    .font(.system(size: IslandType.minimumSize, weight: .medium))
                    .foregroundStyle(IslandPalette.textPrimary.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .top)
                    .padding(.horizontal, IslandSpacing.xxs)
            }
            .padding(.top, IslandSpacing.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(item.isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeTapStyle())
        .disabled(!available)
        .help(help(available: available))
        .accessibilityLabel(item.isEnabled ? item.title : "\(item.title), désactivé")
        .accessibilityValue(action?.activeSystemImage == nil ? "" : (on ? "activé" : "désactivé"))
        .overlay(alignment: .top) {
            // Beside the glyph, outside the tile's own button: a button cannot sit inside another one.
            if isClaude { ClaudeOpenAppButton(context: context).offset(x: 25, y: 7) }
        }
        .overlay(alignment: .topLeading) {
            // Only the Explorer lists hidden tiles: this marks the ones the home does not show.
            if item.isHidden {
                Image(systemName: "eye.slash")
                    .font(.system(size: IslandType.minimumSize, weight: .medium))
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .padding(IslandSpacing.xxs)
                    .accessibilityLabel("masqué")
            }
        }
        .contextMenu {
            if isClaude { ClaudeOpenAppMenuItem(context: context) }
            ForEach(HomeTileMenu.entries(for: item), id: \.self) { entry in
                Button(entry.title, systemImage: entry.systemImage) {
                    switch entry {
                    case .hide: context.home.hideTile(item.id)
                    case .show: context.home.showTile(item.id)
                    }
                }
            }
        }
    }

    private func help(available: Bool) -> String {
        if !item.isEnabled { return "\(item.title) : désactivé. Ouvre les Réglages pour l'activer." }
        return available ? item.title : "\(item.title) : pas encore disponible"
    }
}
