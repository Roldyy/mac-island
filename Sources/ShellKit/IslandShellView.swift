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
            RoundedRectangle(cornerRadius: state.isOpen ? 22 : 10, style: .continuous)
                .fill(ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil && !state.isOpen
                      ? Color.red : Color.black)
            if !state.isOpen {
                context.closedStrip()
                if context.drawsLegacyAlertDot, let alert = context.alert() {
                    // Closed island: a red dot in the right wing while a CPU or memory alert is active.
                    HStack {
                        Spacer()
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                            .padding(.trailing, 4).padding(.top, 12)
                            .accessibilityLabel(alert.title)
                    }
                }
            }
            if state.isOpen { openContent }
        }
        .animation(.easeOut(duration: 0.18), value: state.isOpen)
        .onChange(of: state.isOpen) { _, open in
            if open { context.onOpen(); context.onSectionChange(selectedSectionID) }
        }
        .onChange(of: selectedSectionID) { _, id in
            if state.isOpen { context.onSectionChange(id) }
        }
    }

    private var openContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 38)  // clear of the notch
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
                        .background(selected ? Color.white.opacity(0.16) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
                .accessibilityLabel(group.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 8)
            if let alert = context.alert() {
                Label(alert.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(alert.title). \(alert.message)")
            }
            if context.manualFansActive() {
                // Manual fan mode outlives the island: always say so while it is on.
                Label("Ventilos manuels", systemImage: "fan.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.cyan)
            }
            context.claudePill()  // hidden while idle
            Button { context.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
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
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
