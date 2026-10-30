import SwiftUI

/// "Va quitter: …" with a live countdown. The user can keep an app with one click.
struct PendingQuitList: View {
    let model: AutoQuitModel

    var body: some View {
        if model.pending.isEmpty {
            Text("Aucune app à quitter pour le moment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.dryRun ? "Simulation, quitterait :" : "Va quitter :")
                        .font(.caption.weight(.semibold))
                    ForEach(model.pending) { item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text(remaining(item, now: context.date))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Garder", systemImage: "hand.raised") {
                                if let id = item.bundleID { model.addExclusion(id) }
                            }
                            .labelStyle(.titleOnly)
                            .accessibilityLabel("Garder \(item.name) ouverte")
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func remaining(_ item: PendingQuit, now: Date) -> String {
        let seconds = max(0, Int(item.deadline.timeIntervalSince(now).rounded(.up)))
        return "\(seconds) s"
    }
}
