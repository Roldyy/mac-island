import Foundation
import Testing
@testable import AgentsFeature

/// The parity table (`tasks/parity/agents-strings-en-fr.tsv`, column FR) for every key the page uses,
/// embedded so the test needs no file outside the target. Edit both together.
@Suite struct StringTableTests {
    static let fr: [String: String] = [
        "title": "Agents IA", "restingTitle": "Limites IA",
        "limitsCard": "Limites", "spendCard": "Dépenses", "liveCard": "En cours", "trendCard": "Tendance",
        "modelsCard": "Modèles", "projectsCard": "Projets", "activityCard": "Activité", "resetsCard": "Réinitialisations",
        "today": "Aujourd’hui", "week": "7 jours", "month": "30 jours", "session": "Session", "weekly": "Semaine",
        "estimated": "Estimé depuis ce Mac",
        "waitingForLimits": "Les limites apparaissent après la prochaine réponse",
        "noSession": "Aucune session en cours", "apiValue": "valeur API",
        "tokensFormat": "%@ jetons", "cachedFormat": "%@ depuis le cache", "writtenFormat": "%@ écrits",
        "savedFormat": "%@ économisés grâce au cache", "planMultipleFormat": "%1$@ le prix de %2$@",
        "idle": "Inactif", "noActivity": "Rien sur cette période",
        "empty": "Aucun usage de Claude Code, Codex, d’OpenCode ou de GitHub Copilot pour l’instant. Il apparaît ici dès que l’un d’eux travaille sur ce Mac.",
        "loading": "Lecture de l’usage…",
        "noCards": "Choisissez ce que montre cette page dans les réglages du Dynamic Island.",
        "unpriced": "Certains modèles n’ont pas de prix connu, ce montant est donc un minimum.",
        "streak": "Jours d’affilée", "activeDays": "Jours actifs", "busiestDay": "Jour le plus chargé",
        "finishedFormat": "%@ a terminé", "budgetTitle": "Budget quotidien",
        "leftFormat": "%@ restant", "usedFormat": "%@ utilisé", "cardsTitle": "Cartes",
        "limitsAs": "Afficher les limites en", "remaining": "Restant", "used": "Utilisé",
        "limitFocus": "Limite affichée", "mostUsed": "La plus utilisée", "off": "Désactivé",
        "updatedFormat": "Mis à jour %@",
        "valueNote": "La valeur API est ce que le même travail coûterait aux tarifs publics de l’API. Les forfaits facturent un prix fixe.",
        "budget": "Budget quotidien en valeur API",
    ]

    @Test func everyKeyTheCodeHoldsEqualsTheTableText() {
        #expect(Set(AgentsStrings.table.keys) == Set(Self.fr.keys))
        for (key, expected) in Self.fr {
            #expect(AgentsStrings.table[key] == expected, "clé \(key)")
        }
    }

    @Test func theTableUsesTypographicApostrophesOnly() {
        #expect(AgentsStrings.table.values.allSatisfy { !$0.contains("'") })
    }

    @Test func theLabelsTheViewsDeriveFromKeysAreTheTableText() {
        #expect(AgentsCard.allCases.map(\.title) == ["Limites", "Dépenses", "En cours", "Tendance", "Modèles", "Projets", "Activité", "Réinitialisations"])
        #expect(AgentsLimitFocus.allCases.map(\.title) == ["La plus utilisée", "Session", "Semaine"])
        #expect(AgentsLimitDisplay.allCases.map(\.title) == ["Restant", "Utilisé"])
    }

    @Test func formatsFillPlaceholdersByOrderAndByPosition() {
        #expect(AgentsStrings.format("tokensFormat", "12\u{202F}k") == "12\u{202F}k jetons")
        #expect(AgentsStrings.format("planMultipleFormat", "3,5×", "Max 5x") == "3,5× le prix de Max 5x")
        #expect(AgentsStrings.fill("%2$@ avant %1$@", ["a", "b"]) == "b avant a")
        #expect(AgentsStrings.format("finishedFormat", "100 % fait") == "100 % fait a terminé")
    }
}
