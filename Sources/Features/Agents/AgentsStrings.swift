import Foundation

/// The French wording of the "Agents IA" page, copied verbatim from the parity table
/// (`tasks/parity/agents-strings-en-fr.tsv`, U+2019 apostrophes). Keys are the table's keys.
enum AgentsStrings {
    static let table: [String: String] = [
        "title": "Agents IA",
        "restingTitle": "Limites IA",
        "limitsCard": "Limites",
        "spendCard": "Dépenses",
        "liveCard": "En cours",
        "trendCard": "Tendance",
        "modelsCard": "Modèles",
        "projectsCard": "Projets",
        "activityCard": "Activité",
        "resetsCard": "Réinitialisations",
        "today": "Aujourd’hui",
        "week": "7 jours",
        "month": "30 jours",
        "session": "Session",
        "weekly": "Semaine",
        "estimated": "Estimé depuis ce Mac",
        "waitingForLimits": "Les limites apparaissent après la prochaine réponse",
        "noSession": "Aucune session en cours",
        "apiValue": "valeur API",
        "tokensFormat": "%@ jetons",
        "cachedFormat": "%@ depuis le cache",
        "writtenFormat": "%@ écrits",
        "savedFormat": "%@ économisés grâce au cache",
        "planMultipleFormat": "%1$@ le prix de %2$@",
        "idle": "Inactif",
        "noActivity": "Rien sur cette période",
        "empty": "Aucun usage de Claude Code, Codex, d’OpenCode ou de GitHub Copilot pour l’instant. Il apparaît ici dès que l’un d’eux travaille sur ce Mac.",
        "loading": "Lecture de l’usage…",
        "noCards": "Choisissez ce que montre cette page dans les réglages du Dynamic Island.",
        "unpriced": "Certains modèles n’ont pas de prix connu, ce montant est donc un minimum.",
        "streak": "Jours d’affilée",
        "activeDays": "Jours actifs",
        "busiestDay": "Jour le plus chargé",
        "finishedFormat": "%@ a terminé",
        "budgetTitle": "Budget quotidien",
        "leftFormat": "%@ restant",
        "usedFormat": "%@ utilisé",
        "cardsTitle": "Cartes",
        "limitsAs": "Afficher les limites en",
        "remaining": "Restant",
        "used": "Utilisé",
        "limitFocus": "Limite affichée",
        "mostUsed": "La plus utilisée",
        "off": "Désactivé",
        "updatedFormat": "Mis à jour %@",
        "valueNote": "La valeur API est ce que le même travail coûterait aux tarifs publics de l’API. Les forfaits facturent un prix fixe.",
        "budget": "Budget quotidien en valeur API",
    ]

    /// A missing key shows the key itself: loud on screen, and the coverage test fails first.
    static func text(_ key: String) -> String { table[key] ?? key }

    static func format(_ key: String, _ arguments: String...) -> String { fill(text(key), arguments) }

    /// Fills `%1$@`, `%2$@` by position, then plain `%@` in order. No `String(format:)`: the
    /// arguments are plain Strings and a stray `%` in a value must stay as it is.
    static func fill(_ template: String, _ arguments: [String]) -> String {
        var result = template
        for (index, argument) in arguments.enumerated() {
            result = result.replacingOccurrences(of: "%\(index + 1)$@", with: argument)
        }
        for argument in arguments {
            guard let range = result.range(of: "%@") else { break }
            result.replaceSubrange(range, with: argument)
        }
        return result
    }

    // Wording the table does not hold: French, short, listed in the lane report.
    static let settingsLabel = "Réglages de la page"
    static let closeLabel = "Fermer"
    static let periodLabel = "Période"
    static let moveUp = "Monter"
    static let moveDown = "Descendre"
    static let showCard = "Afficher la carte"
    static let tokensToggle = "Jetons"
    static let costToggle = "Coût"
    static let renewsAt = "Renouvellement à"
    static let working = "Travaille"
    static let waiting = "Attend"
}
