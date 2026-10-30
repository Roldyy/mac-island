import SwiftUI

struct ShelfPane: View {
    @Bindable var model: ShelfModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.shelfEnabled {
                Text("L'étagère est désactivée dans les réglages.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            } else if model.items.isEmpty {
                Text("Déposez des fichiers ici pour les garder à portée de main.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.items) { item in
                            let url = model.url(for: item)
                            FileTile(name: item.displayName,
                                     icon: model.icon(forPath: url?.path ?? item.path),
                                     available: url != nil,
                                     dragProvider: { model.dragProvider(for: item) },
                                     reveal: { model.reveal(item) },
                                     remove: { model.remove(item) })
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Tout retirer", systemImage: "trash") { model.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityLabel("Retirer tous les fichiers de l'étagère")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(model.isDropTargeted ? 0.6 : 0.12), style: StrokeStyle(lineWidth: 1, dash: [4]))
        }
        .onDrop(of: ["public.file-url"], isTargeted: $model.isDropTargeted) { providers in
            model.handleDrop(providers)
        }
        .accessibilityLabel("Étagère, zone de dépôt de fichiers")
        .onAppear { model.refreshItems() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshItems()
        }
    }
}
