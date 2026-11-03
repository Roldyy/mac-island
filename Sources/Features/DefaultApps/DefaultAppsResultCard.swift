import IslandUI
import SwiftUI

/// Per-item outcome of the last apply or undo.
struct DefaultAppsResultCard: View {
    let model: DefaultAppsModel
    let report: ApplyReport

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Résultat", subtitle: summary)
                if let notice = report.notice {
                    Text(notice).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                        ForEach(report.outcomes) { outcome in
                            IslandRow(outcome.title, subtitle: detail(outcome), status: status(outcome))
                        }
                    }
                }
                .frame(maxHeight: 220)
                Button("Fermer le résultat") { model.dismissReport() }.buttonStyle(IslandButtonStyle())
            }
        }
    }

    private var summary: String {
        "\(report.successCount) réussi\(report.successCount > 1 ? "s" : ""), \(report.failureCount) échec\(report.failureCount > 1 ? "s" : ""), \(report.skippedCount) non tenté\(report.skippedCount > 1 ? "s" : "")."
    }

    private func status(_ outcome: ItemOutcome) -> IslandStatus {
        switch outcome.result {
        case .success: .success
        case .unverified: .warning
        case .failure: .danger
        case .skipped: .neutral
        }
    }

    private func detail(_ outcome: ItemOutcome) -> String {
        switch outcome.result {
        case .success: "Changé."
        case .unverified: "macOS a répondu sans changer la valeur lue : vérifiez dans le Finder."
        case .failure(let message): message
        case .skipped(let reason): reason
        }
    }
}
