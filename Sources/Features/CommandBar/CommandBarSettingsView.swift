import SwiftUI

/// The "Commandes" tab: hotkey, enabled flag, habits and sources.
struct CommandBarSettingsView: View {
    @Bindable var controller: CommandBarController

    private static let sourceLabels: [(id: String, label: String)] = [
        ("apps", "Applications"), ("files", "Fichiers (par nom)"), ("calculator", "Calculatrice"),
        ("web", "Recherche web"), ("commands", "Commandes de l\u{2019}\u{00EE}le"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Barre de commandes", isOn: $controller.enabled)
                    .onChange(of: controller.enabled) { controller.enabledChanged() }

                HStack(spacing: 8) {
                    Text("Raccourci")
                    Text(controller.hotkeyDisplay)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel("Raccourci actuel \(controller.hotkeyDisplay)")
                    Text(controller.status.message)
                        .foregroundStyle(controller.status == .conflict ? Color.orange : .white.opacity(0.6))
                    Spacer()
                }

                HStack(spacing: 8) {
                    TextField("option+command:9", text: $controller.hotkeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .accessibilityLabel("Raccourci, format option+espace")
                        .onSubmit { controller.applyHotkey(controller.hotkeyDraft) }
                    Button("Appliquer") { controller.applyHotkey(controller.hotkeyDraft) }
                        .accessibilityHint("Enregistre le raccourci saisi")
                    if controller.hotkeyInvalid {
                        Text("Raccourci invalide").foregroundStyle(.orange)
                    }
                }

                Divider().overlay(.white.opacity(0.12))

                Toggle("M\u{00E9}moriser les habitudes d\u{2019}usage", isOn: $controller.habitsEnabled)
                    .onChange(of: controller.habitsEnabled) { controller.habitsChanged() }
                Text("Seuls les identifiants des r\u{00E9}sultats et leur nombre d\u{2019}usage sont gard\u{00E9}s, jamais le texte tap\u{00E9}. D\u{00E9}sactiver efface tout.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                Button("Effacer les habitudes", role: .destructive) { controller.clearHabits() }

                Divider().overlay(.white.opacity(0.12))

                Text("Sources").font(.headline)
                ForEach(Self.sourceLabels, id: \.id) { entry in
                    Toggle(entry.label, isOn: sourceBinding(entry.id))
                }
            }
            .toggleStyle(.switch)
            .foregroundStyle(.white)
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }

    private func sourceBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { controller.sources[id] ?? true },
                set: { controller.sources[id] = $0; controller.sourceChanged(id) })
    }
}
