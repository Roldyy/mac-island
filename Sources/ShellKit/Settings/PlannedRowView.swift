import IslandUI
import SwiftUI

/// A control of the reference page that does not exist here yet: greyed, inert, marked "Bientôt".
/// Never a working switch: every control is disabled and bound to a constant.
struct PlannedRowView: View {
    let item: SettingsItem

    var body: some View {
        HStack(spacing: IslandSpacing.s) {
            Text(item.label)
                .font(.islandBody)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            control.disabled(true)
            IslandBadge("Bientôt", status: .info)
        }
        .frame(minHeight: IslandMetrics.controlHeight)
        .opacity(0.6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var control: some View {
        switch item.kind {
        case .toggle:
            // The island switch draws its own label, so the label stays empty here.
            Toggle(isOn: .constant(false)) { EmptyView() }.toggleStyle(IslandToggleStyle()).fixedSize()
                .accessibilityLabel(item.label)
        case .menu:
            Text(item.value).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        case .choices:
            Picker(item.label, selection: .constant(item.value.isEmpty ? (item.options.first ?? "") : item.value)) {
                ForEach(item.options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        case .slider:
            Slider(value: .constant(0.5)).frame(width: 120)
        case .field, .stepper:
            Text("—").font(.islandCaption)
        case .button, .link:
            Text("Ouvrir").font(.islandCaptionEmphasis)
        case .caption, .heading:
            EmptyView()
        }
    }
}
