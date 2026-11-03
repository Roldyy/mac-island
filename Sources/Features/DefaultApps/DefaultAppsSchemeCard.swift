import IslandUI
import SwiftUI

/// Advanced: one URL scheme the user picks by name. Never touched otherwise.
struct DefaultAppsSchemeCard: View {
    let model: DefaultAppsModel

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Liens et schémas d’URL",
                             subtitle: "Avancé. Seulement pour un schéma que vous choisissez. http, https, mailto et les autres schémas système demandent une confirmation en plus.")
                HStack(spacing: IslandSpacing.s) {
                    Menu(appTitle) {
                        ForEach(model.schemeApps) { app in
                            Button(app.name) { model.selectSchemeApp(app.id) }
                        }
                    }
                    .fixedSize()
                    .accessibilityLabel("Application pour le schéma")
                    if let app = model.schemeAppID.flatMap(model.scan.app) {
                        Menu(model.scheme.map { "\($0):" } ?? "Choisir un schéma") {
                            ForEach(app.declared.schemes.sorted(), id: \.self) { scheme in
                                Button(ProtectionPolicy.isProtected(scheme: scheme) ? "\(scheme): (sensible)" : "\(scheme):") {
                                    model.selectScheme(scheme)
                                }
                            }
                        }
                        .fixedSize()
                        .accessibilityLabel("Schéma d’URL")
                    }
                }
                if let scheme = model.scheme, ProtectionPolicy.isProtected(scheme: scheme) {
                    DefaultAppsCheckRow(title: "Je confirme : « \(scheme): » est un schéma sensible",
                                        subtitle: "Il ouvre vos liens, vos e-mails ou vos fichiers : un mauvais choix se remarque tout de suite.",
                                        isOn: model.schemeConfirmedProtected) {
                        model.setSchemeConfirmed(!model.schemeConfirmedProtected)
                    }
                }
                Button("Voir l’aperçu du schéma") { model.buildSchemePreview() }
                    .buttonStyle(IslandButtonStyle())
                    .disabled(model.schemeAppID == nil || model.scheme == nil || model.isApplying)
            }
        }
    }

    private var appTitle: String {
        model.schemeAppID.flatMap(model.scan.app)?.name ?? "Choisir l’application"
    }
}
