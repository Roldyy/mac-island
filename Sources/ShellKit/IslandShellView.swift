import IslandKit
import IslandUI
import SwiftUI

/// Content of the island panel: the closed strip, or the open island (Spacieuse home, Explorer, feature pages).
public struct IslandShellView: View {
    @EnvironmentObject private var state: IslandState
    private let context: ShellContext

    public init(context: ShellContext) { self.context = context }

    public var body: some View {
        ZStack(alignment: .top) {
            if !state.isOpen {
                closedBackground
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
            } else {
                HomeIslandContent(context: context, notchWidth: state.notchWidth, notchHeight: state.notchHeight)
            }
        }
        .islandAnimation(.easeOut(duration: 0.18), value: state.isOpen)
        .onAppear { context.onOpenSize(context.panelSize) }
        // The panel follows the size mode, the Explorer and each page; Reduce Motion cuts the resize animation.
        .onChange(of: context.panelSize) { _, size in context.onOpenSize(size) }
        .onChange(of: state.isOpen) { _, open in
            guard open else { return }
            context.onOpenSize(context.panelSize)
            context.home.refreshLevels()
            context.onOpen()
            context.onSectionChange(openPageID)
        }
        .onChange(of: openPageID) { _, id in
            if state.isOpen { context.onSectionChange(id) }
        }
    }

    private var openPageID: String? {
        if case .page(let id) = context.navigation.route { id } else { nil }
    }

    /// Closed: solid black like the notch.
    private var closedBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil
                  ? IslandPalette.statusDanger.color : IslandSurface.notchBlack)
    }
}
