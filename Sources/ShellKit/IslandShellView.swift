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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let context: ShellContext
    /// The environment value is read-only, so tests force Reduce Motion here; the app leaves it nil.
    private let reduceMotionOverride: Bool?
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    /// Feature pages and the Explorer are mounted from the moment the island opens until the close animation
    /// ends (they own tasks, timers and focus); the home is built once and stays.
    @State private var contentLive = false
    /// The closed strip (a one-second clock while Claude works) is unmounted once the island is fully open.
    @State private var stripLive = true

    public init(context: ShellContext, reduceMotionOverride: Bool? = nil) {
        self.context = context
        self.reduceMotionOverride = reduceMotionOverride
    }

    private static let debugBackground = ProcessInfo.processInfo.environment["MIS_DEBUG"] != nil

    public var body: some View {
        let progress: Double = state.isOpen ? 1 : 0
        let closedSize = CGSize(width: state.closedWidth, height: state.closedHeight)
        // One source of truth for the open size: the route decides it, this view takes it at once, and the
        // reveal shape is that size too. The panel window (bigger for a moment on a shrink, see
        // `IslandFramePlan`) only holds it: the silhouette never lags behind the route.
        let open = context.panelSize
        // The ZStack is exactly the panel (the clear base fills whatever the window proposes). The open layer is a
        // `background`: it is laid out at its own fixed size, may overflow the panel (the window clips it), and
        // never takes part in the size of this view. Sized by it, the root would be taller than a closed panel
        // and the hosting view would centre it vertically, pushing the closed pill out of the window.
        ZStack(alignment: .top) {
            Color.clear
            if stripLive {
                closedLayer
                    .frame(width: closedSize.width, height: closedSize.height)
                    // The closed island is lopsided when its wings differ: its centre is off the notch's.
                    .offset(x: state.closedCenterOffset)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: closedSize)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state.closedCenterOffset)
                    // The panel is the closed frame at rest and the centred open frame otherwise: the offset
                    // between them follows the window at once and is never animated.
                    .offset(x: -state.panelOffset)
                    .animation(nil, value: state.panelOffset)
                    .modifier(IslandClosedReveal(progress: progress))
                    .allowsHitTesting(!state.isOpen)
            }
        }
        .background(alignment: .top) {
            Color.clear
                .frame(width: open.width, height: open.height)
                .overlay(alignment: .top) {
                    HomeIslandContent(context: context, notchWidth: state.notchWidth, notchHeight: state.notchHeight,
                                      isOpen: state.isOpen, isLive: contentLive)
                        .frame(width: open.width, height: open.height, alignment: .top)
                }
                .modifier(HomeOpenReveal(progress: progress, closedSize: closedSize, closedOffset: state.closedShift,
                                         translucent: context.home.translucentBackground))
                .allowsHitTesting(state.isOpen)
                .accessibilityHidden(!state.isOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
