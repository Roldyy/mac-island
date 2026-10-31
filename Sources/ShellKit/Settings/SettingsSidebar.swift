import IslandUI
import SwiftUI

/// Search field and the list of pages, grouped by section. A query flattens the list to its matches.
struct SettingsSidebar: View {
    @Bindable var router: SettingsRouter

    private var selection: Binding<String?> {
        Binding(get: { router.selection }, set: { if let id = $0 { router.open(id) } })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: IslandSpacing.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Rechercher dans les réglages", text: $router.query)
                    .textFieldStyle(.plain)
                    .font(.islandBody)
                    .onSubmit {
                        if let first = SettingsSearch.filter(SettingsPageCatalog.all, query: router.query).first {
                            router.open(first.id)
                        }
                    }
                if !router.query.isEmpty {
                    Button("Effacer la recherche", systemImage: "xmark.circle.fill") { router.query = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(IslandSpacing.s)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: IslandRadius.small))
            .padding(IslandSpacing.s)

            List(selection: selection) {
                if router.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(SettingsSearch.sections(SettingsPageCatalog.all), id: \.section) { group in
                        Section(group.section.title) {
                            ForEach(group.pages) { row($0) }
                        }
                    }
                } else {
                    let matches = SettingsSearch.filter(SettingsPageCatalog.all, query: router.query)
                    if matches.isEmpty {
                        Text("Aucun réglage trouvé").font(.islandCaption).foregroundStyle(.secondary)
                    }
                    ForEach(matches) { row($0) }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func row(_ page: SettingsPage) -> some View {
        Label(page.title, systemImage: page.symbol)
            .font(.islandBody)
            .lineLimit(1)
            .tag(page.id)
    }
}
