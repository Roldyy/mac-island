import IslandUI
import SwiftUI

/// The actions of a chip, in the popover its tap opens. A destructive action (or one that asks) changes its label to
/// "Confirmer" on the first click and runs on the second; the label goes back after `StatusChipConfirmation.window`.
struct StatusChipActionStrip: View {
    let actions: [StatusChipAction]
    let dismiss: () -> Void

    @State private var armed: StatusChipConfirmation.Armed?

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            ForEach(actions) { action in row(action) }
        }
        .padding(IslandSpacing.s)
        .task(id: armed) {
            // The countdown only runs while a button is armed; a new click restarts it (the id changed).
            guard armed != nil else { return }
            try? await Task.sleep(for: .seconds(StatusChipConfirmation.window))
            if !Task.isCancelled { armed = nil }
        }
    }

    private func row(_ action: StatusChipAction) -> some View {
        let isArmed = StatusChipConfirmation.isArmed(armed, for: action.id, now: .now)
        return Button { tap(action) } label: {
            if isArmed {
                Label("Confirmer", systemImage: "checkmark")
            } else if let image = action.systemImage {
                Label(action.title, systemImage: image)
            } else {
                Text(action.title)
            }
        }
        .buttonStyle(IslandButtonStyle(action.isDestructive ? .destructive : .standard))
        .accessibilityLabel(isArmed ? "Confirmer : \(action.title)" : action.title)
    }

    private func tap(_ action: StatusChipAction) {
        switch StatusChipConfirmation.decide(action, armed: armed, now: .now) {
        case .perform:
            armed = nil
            action.handler()
            dismiss()
        case .arm:
            armed = StatusChipConfirmation.Armed(actionID: action.id, at: .now)
        }
    }
}
