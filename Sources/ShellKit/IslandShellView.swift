import IslandKit
import IslandUI
import SwiftUI

/// Content of the island panel: the closed strip, or the open island (Spacieuse home, Explorer, feature pages).
///
/// Both layers exist all the time. Opening and closing is ONE animation of one progress value
/// (`IslandRevealCurve`): the open layer is laid out once at its final size and clipped by a growing shape,
/// the closed strip fades out underneath. The panel is not resized per frame (`IslandController`).
public struct IslandShellView: View {
    @EnvironmentObject private var state: IslandState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let context: ShellContext

    /// Feature pages and the Explorer are mounted from the moment the island opens until the close animation
    /// ends (they own tasks, timers and focus); the home is built once and stays.
    @State private var contentLive = false
    /// The closed strip (a one-second clock while Claude works) is unmounted once the island is fully open.
    @State private var stripLive = true

    public init(context: ShellContext) { self.context = context }

    private static let debugBackground = ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil

    public var body: some View {
        let progress: Double = state.isOpen ? 1 : 0
        let closedSize = CGSize(width: state.closedWidth, height: state.closedHeight)
        ZStack(alignment: .top) {
            // Fills the panel; the open island is laid out at its own fixed size inside it.
            Color.clear
                .overlay(alignment: .top) {
                    HomeIslandContent(context: context, notchWidth: state.notchWidth, notchHeight: state.notchHeight,
                                      isOpen: state.isOpen, isLive: contentLive)
                        .frame(width: context.panelSize.width, height: context.panelSize.height, alignment: .top)
                }
                .modifier(IslandOpenReveal(progress: progress, closedSize: closedSize,
                                           translucent: context.home.translucentBackground))
                .allowsHitTesting(state.isOpen)
                .accessibilityHidden(!state.isOpen)
            if stripLive {
                closedLayer
                    .frame(width: closedSize.width, height: closedSize.height)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: closedSize)
                    .modifier(IslandClosedReveal(progress: progress))
                    .allowsHitTesting(!state.isOpen)
            }
        }
        .animation(IslandRevealCurve.animation(opening: state.isOpen, reduceMotion: reduceMotion), value: state.isOpen)
        .onAppear { context.onOpenSize(context.panelSize) }
        // The panel follows the size mode, the Explorer and each page; Reduce Motion cuts the resize animation.
        .onChange(of: context.panelSize) { _, size in context.onOpenSize(size) }
        .onChange(of: state.isOpen) { _, open in
            if open {
                contentLive = true
                context.onOpenSize(context.panelSize)
                runAfterFirstFrames()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(IslandRevealCurve.openDuration + 0.05))
                    if state.isOpen { stripLive = false }
                }
            } else {
                stripLive = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(IslandRevealCurve.settleDelay))
                    if !state.isOpen { contentLive = false }
                }
            }
        }
        .onChange(of: openPageID) { _, id in
            if state.isOpen { context.onSectionChange(id) }
        }
    }

    /// Work that is not needed to draw the first frames of the animation waits a few frames, so the main
    /// thread is free while the shape starts to grow.
    private func runAfterFirstFrames() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard state.isOpen else { return }
            context.onOpen()
            context.onSectionChange(openPageID)
        }
    }

    private var openPageID: String? {
        if case .page(let id) = context.navigation.route { id } else { nil }
    }

    private var closedLayer: some View {
        ZStack(alignment: .top) {
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
        }
    }

    /// Closed: solid black like the notch.
    private var closedBackground: some View {
        RoundedRectangle(cornerRadius: IslandRevealCurve.closedBottomRadius, style: .continuous)
            .fill(Self.debugBackground ? IslandPalette.statusDanger.color : IslandSurface.notchBlack)
    }
}
