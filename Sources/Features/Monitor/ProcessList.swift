import SwiftUI

/// Top processes by one criterion: name, pid and one figure. No command line.
struct ProcessList: View {
    let title: String
    let rows: [ProcessUsage]
    let figure: (ProcessUsage) -> String
    var emptyText = "En attente de mesure"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            if rows.isEmpty {
                Text(emptyText).font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Text(row.name).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(figure(row)).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name), \(figure(row))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
