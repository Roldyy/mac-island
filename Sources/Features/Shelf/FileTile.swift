import SwiftUI

/// One file: icon, name, optional unavailable mark. Drag out with the file URL only.
struct FileTile: View {
    let name: String
    let icon: NSImage
    let available: Bool
    let dragProvider: () -> NSItemProvider
    let reveal: () -> Void
    var remove: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(available ? 1 : 0.35)
                .accessibilityHidden(true)
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(available ? 0.9 : 0.5))
            if !available {
                Text("Indisponible")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 76)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onDrag { dragProvider() }
        .contextMenu {
            Button("Afficher dans le Finder", systemImage: "folder", action: reveal)
                .disabled(!available)
            if let remove { Button("Retirer de l'étagère", systemImage: "xmark", action: remove) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? name : "\(name), indisponible")
        .accessibilityHint("Glisser vers une autre app. Actions : afficher dans le Finder.")
        .accessibilityAction(named: "Afficher dans le Finder", reveal)
    }
}
