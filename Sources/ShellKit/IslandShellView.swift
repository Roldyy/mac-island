import IslandKit
import IslandUI
import SwiftUI

/// Content of the island panel: the closed strip, or four fixed tabs with a sub-control and the quick bar.
public struct IslandShellView: View {
    @EnvironmentObject private var state: IslandState
    private let context: ShellContext

    public init(context: ShellContext) { self.context = context }

    public var body: some View {
        ZStack(alignment: .top) {
            background
            if !state.isOpen {
                context.closedStrip()
                if context.drawsLegacyAlertDot, let alert = context.alert() {
                    // Closed island: a red dot in the right wing while a CPU or memory alert is active.
                    HStack {
                        Spacer()
                        Circle().fill(IslandPalette.statusDanger.color).frame(width: 8, height: 8)
                            .padding(.trailing, 4).padding(.top, 12)
                            .accessibilityLabel(alert.title)
                    }
                }
            }
            if state.isOpen { openContent }
        }
        .islandAnimation(.easeOut(duration: 0.18), value: state.isOpen)
        .onChange(of: state.isOpen) { _, open in
            if open { context.onOpen(); context.onSectionChange(selectedSectionID) }
        }
        .onChange(of: selectedSectionID) { _, id in
            if state.isOpen { context.onSectionChange(id) }
        }
    }

    /// Closed: solid black like the notch. Open: glass, with the band behind the notch kept solid black.
    @ViewBuilder private var background: some View {
        if state.isOpen {
            ZStack(alignment: .top) {
                Color.clear.islandGlass(cornerRadius: Self.openRadius)
                UnevenRoundedRectangle(topLeadingRadius: Self.openRadius, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: Self.openRadius,
                                       style: .continuous)
                    .fill(IslandSurface.notchBlack)
                    .frame(height: ShellLayout.topBandHeight)
            }
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil
                      ? IslandPalette.statusDanger.color : IslandSurface.notchBlack)
        }
    }

    private static let openRadius: CGFloat = 22

    private var openContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, ShellLayout.topBandHeight)  // clear of the notch
                .padding(.bottom, 8)
            sectionPicker
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            QuickAccessBar(model: context.quickAccess).padding(.top, 8)
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private var header: some View {
        HStack(spacing: 4) {
            // Four titles, always visible, same slots whatever is selected: nothing shifts on click.
            ForEach(ShellLayout.groups) { group in
                let selected = context.navigation.selectedGroup == group.id
                Button { context.navigation.selectedGroup = group.id } label: {
                    Label(group.title, systemImage: group.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(selected ? IslandPalette.textPrimary.color.opacity(0.12) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? IslandPalette.textPrimary.color : IslandPalette.textSecondary.color)
                .accessibilityLabel(group.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 8)
            if let alert = context.alert() {
                Label(alert.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandStatus.warning.color)
                    .accessibilityLabel("\(alert.title). \(alert.message)")
            }
            if context.manualFansActive() {
                // Manual fan mode outlives the island: always say so while it is on.
                Label("Ventilos manuels", systemImage: "fan.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandStatus.info.color)
            }
            context.claudePill()  // hidden while idle
            Button { context.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .foregroundStyle(IslandPalette.textSecondary.color)
                .help("Réglages")
                .accessibilityLabel("Réglages")
        }
    }

    private var group: ShellGroup {
        ShellLayout.groups.first { $0.id == context.navigation.selectedGroup } ?? ShellLayout.groups[0]
    }

    private var visibleSections: [ShellSection] {
        ShellLayout.visibleSections(of: group) { context.registry.isEnabled($0) }
    }

    private var selectedSectionID: String? {
        ShellLayout.resolvedSection(remembered: context.navigation.sections[group.id], visible: visibleSections)
    }

    @ViewBuilder private var sectionPicker: some View {
        if visibleSections.count > 1, let current = selectedSectionID {
            Picker("Section", selection: Binding(
                get: { current },
                set: { context.navigation.sections[group.id] = $0 }
            )) {
                ForEach(visibleSections) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var content: some View {
        if let id = selectedSectionID, let tab = context.tabs.first(where: { $0.id == id }) {
            tab.makeView()
        } else {
            Text("Cet onglet est désactivé dans les Réglages.")
                .font(.system(size: 12)).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }
}
