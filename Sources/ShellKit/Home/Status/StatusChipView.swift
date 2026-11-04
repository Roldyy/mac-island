import IslandUI
import SwiftUI

/// One capsule: glyph (or progress ring), main text, dim second text, and the status symbol when the level is not
/// normal (color never travels alone). A chip with actions is a button that opens them in a popover.
struct StatusChipView: View {
    let reading: StatusChipReading

    @State private var showsActions = false

    static let height: CGFloat = HomeGeometry.statusChipRow - 2 * IslandSpacing.xxs

    var body: some View {
        if reading.actions.isEmpty {
            capsule
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reading.accessibilityText)
        } else {
            Button { showsActions.toggle() } label: { capsule }
                .buttonStyle(HomeTapStyle())
                .popover(isPresented: $showsActions, arrowEdge: .bottom) {
                    StatusChipActionStrip(actions: reading.actions) { showsActions = false }
                }
                .accessibilityLabel(reading.accessibilityText)
                .accessibilityHint("Affiche les actions")
        }
    }

    // MARK: - Capsule

    private var capsule: some View {
        HStack(spacing: IslandSpacing.xs) {
            glyph
            Text(reading.primary)
                .font(.islandCaptionEmphasis)
            if let secondary = reading.secondary {
                Text(secondary)
                    .font(.islandFootnote)
                    .foregroundStyle(secondaryColor)
            }
            if reading.level != .normal {
                Image(systemName: reading.level.status.symbol)
                    .font(.islandFootnote)
                    .accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(primaryColor)
        .padding(.horizontal, IslandSpacing.s)
        .frame(height: Self.height)
        .background(fill, in: Capsule())
        .contentShape(Capsule())
    }

    @ViewBuilder private var glyph: some View {
        if let progress = reading.progress {
            ZStack {
                Circle().stroke(primaryColor.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(primaryColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
        } else {
            Image(systemName: reading.symbol)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Tint

    /// A normal chip stays discreet (neutral fill, primary text); attention and alert take the status color.
    private var primaryColor: Color {
        reading.level == .normal ? IslandPalette.textPrimary.color : reading.level.status.color
    }

    private var secondaryColor: Color {
        reading.level == .normal ? IslandPalette.textSecondary.color : reading.level.status.color
    }

    private var fill: Color {
        reading.level == .normal
            ? IslandPalette.textPrimary.color.opacity(0.10)
            : reading.level.status.color.opacity(0.18)
    }
}
