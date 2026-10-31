import IslandUI
import SwiftUI

/// A small segmented control drawn with palette tokens. The system one is an AppKit view: it cannot be
/// rendered in a snapshot and ignores the island's contrast tokens.
struct AgentsSegmentedControl<Value: Hashable & Identifiable>: View {
    let items: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var label = ""

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item == selection
                Button { selection = item } label: {
                    Text(title(item))
                        .font(.islandCaptionEmphasis)
                        .foregroundStyle(selected ? IslandPalette.textPrimary.color : IslandPalette.textSecondary.color)
                        .padding(.horizontal, IslandSpacing.m)
                        .frame(minHeight: IslandMetrics.controlHeight - 4)
                        .background(selected ? IslandPalette.textPrimary.color.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: IslandRadius.small - 1, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(IslandPalette.textPrimary.color.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: IslandRadius.small + 1, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
