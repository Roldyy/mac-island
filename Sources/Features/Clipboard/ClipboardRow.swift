import SwiftUI

struct ClipboardRow: View {
    let entry: ClipboardEntry
    let model: ClipboardModel

    var body: some View {
        HStack(spacing: 6) {
            Button { model.putBack(entry) } label: {
                HStack(spacing: 8) {
                    leading
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(entry.copiedAt, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copier à nouveau : \(accessibleSummary)")

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
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private var preview: String {
        switch entry.kind {
        case .text: entry.text
        case .files: entry.text
        case .image: "Image \(entry.imageWidth ?? 0) × \(entry.imageHeight ?? 0)"
        }
    }

    private var accessibleSummary: String {
        switch entry.kind {
        case .image: "image"
        default: String(preview.prefix(80))
        }
    }

    @ViewBuilder private var leading: some View {
        switch entry.kind {
        case .image: ThumbnailView(entry: entry, model: model)
        case .files: Image(systemName: "doc").frame(width: 28, height: 28).foregroundStyle(.white.opacity(0.7))
        case .text: Image(systemName: "text.alignleft").frame(width: 28, height: 28).foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct ThumbnailView: View {
    let entry: ClipboardEntry
    let model: ClipboardModel
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
        .task(id: entry.id) { image = await model.thumbnail(for: entry) }
    }
}
