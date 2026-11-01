import Foundation

/// One release of the changelog shown on the "Nouveautés" page.
public struct ChangelogEntry: Identifiable, Equatable, Sendable {
    public let version: String
    public let date: String
    public let added: [String]
    public let changed: [String]
    public let fixed: [String]
    /// One or two sentences on the release as a whole ("Résumé").
    public let summary: String
    public var id: String { version }

    public init(version: String, date: String, summary: String = "", added: [String], changed: [String], fixed: [String]) {
        self.version = version
        self.date = date
        self.added = added
        self.changed = changed
        self.fixed = fixed
        self.summary = summary
    }

    public static let all: [ChangelogEntry] = [
        ChangelogEntry(
            version: "2.0 (en cours)", date: "2026-10",
            summary: "Mac Island reprend les fonctions de Vorssaint 3.4.2 sous l’encoche : une seule île, 67 pages de réglages, et vos réglages repris tels quels.",
            added: [
                "Fenêtre de réglages à 67 pages, avec recherche et historique.",
                "Reprise automatique de vos réglages depuis l’ancienne app.",
                "Écran Claude : limites du forfait, dépenses, tendance et activité.",
                "Les six boutons d’accès rapide font leur vraie action.",
                "Ouverture à la connexion, apparence, raccourci global pour Garder éveillé.",
                "Sauvegarde et restauration des réglages.",
            ],
            changed: [
                "L’île sombre reste lisible sur tous les fonds.",
                "Chaque fonction a son interrupteur, son état et ses autorisations.",
            ],
            fixed: [
                "Les autorisations accordées dans Réglages Système sont reprises sans relancer l’app.",
            ]),
        ChangelogEntry(
            version: "1.0.0", date: "2026-09",
            added: ["Première version publiée : île, presse-papiers, étagère, mixeur, moniteur, barre de commande."],
            changed: [], fixed: []),
    ]
}
