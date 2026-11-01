import IslandKit
import SwiftUI

/// The tab: history and scratchpad segments. Black island, system font, no hover side effects.
struct ClipboardView: View {
    @Bindable var model: ClipboardModel
    @Environment(\.islandActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Section", selection: $model.segment) {
                ForEach(ClipboardSegment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Section du presse-papiers")

            switch model.segment {
            case .history: HistoryPane(model: model)
            case .scratchpad: ScratchpadPane(model: model)
            }

            Text(model.plainPasteStatus)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .accessibilityLabel(model.plainPasteStatus)

            if !model.historyShortcutStatus.isEmpty {
                Text(model.historyShortcutStatus)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .task {
            model.start()
            model.purgeExpired()
            model.refreshAccessibility()
        }
    }
}
