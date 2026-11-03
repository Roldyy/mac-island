import IslandUI
import SwiftUI

/// A tick box that is a real button (symbol and label say the state, never colour alone).
struct DefaultAppsCheckRow: View {
    let title: String
    let subtitle: String?
    let isOn: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: IslandSpacing.s) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.islandBody)
                    .foregroundStyle(isOn ? IslandPalette.accent.color : IslandPalette.textSecondary.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                    Text(title).font(.islandBody).foregroundStyle(IslandPalette.textPrimary.color)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A selectable line (icon, title, caption) used by the app lists.
struct DefaultAppsSelectRow<Icon: View>: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: IslandSpacing.s) {
                icon
                VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                    Text(title).font(.islandBody).foregroundStyle(IslandPalette.textPrimary.color)
                    Text(subtitle).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                Spacer(minLength: IslandSpacing.s)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.islandBody).foregroundStyle(IslandPalette.accent.color).accessibilityHidden(true)
                }
            }
            .padding(.vertical, IslandSpacing.xs)
            .padding(.horizontal, IslandSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? IslandPalette.accent.color.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
