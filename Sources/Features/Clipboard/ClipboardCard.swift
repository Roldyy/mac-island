import SwiftUI

/// One entry of the "Cartes" layout: a small tile, the content first, the age and the two actions under it.
struct ClipboardCard: View {
    let entry: ClipboardEntry
    let model: ClipboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { model.putBack(entry) } label: {
                content
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copier à nouveau : \(summary)")

            HStack(spacing: 6) {
                Text(entry.copiedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(entry.pinned ? "Désépingler" : "Épingler", systemImage: entry.pinned ? "pin.fill" : "pin") {
                    model.togglePin(entry)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(entry.pinned ? Color.yellow : .white.opacity(0.5))
                Button("Supprimer", systemImage: "xmark") { model.remove(entry) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .image:
            ThumbnailView(entry: entry, model: model)
        case .files:
            Label(entry.text, systemImage: "doc")
                .font(.caption).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading)
        case .text:
            Text(entry.text)
                .font(.caption).foregroundStyle(.white).lineLimit(4).multilineTextAlignment(.leading)
        }
    }

    private var summary: String {
        switch entry.kind {
        case .image: "image"
        default: String(entry.text.prefix(80))
        }
    }
}
