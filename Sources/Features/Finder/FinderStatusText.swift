/// Status lines for the tab (French, like the rest of the island). Pure, so they are tested.
enum FinderStatusText {
    static func permissions(accessibility: Bool, inputMonitoring: Bool, tapRunning: Bool, enabled: Bool) -> String {
        if !accessibility { return "Accessibilité : non autorisée (Réglages Système)" }
        if !inputMonitoring { return "Surveillance de l'entrée : non autorisée (Réglages Système)" }
        if !enabled { return "Accessibilité : autorisée, fonctions désactivées" }
        return tapRunning ? "Accessibilité : autorisée, raccourcis actifs" : "Accessibilité : autorisée, raccourcis inactifs"
    }

    static func automation(_ s: AutomationStatus) -> String {
        switch s {
        case .granted: "Automatisation Finder : autorisée"
        case .denied: "Automatisation Finder : refusée (Réglages Système)"
        case .notDetermined: "Automatisation Finder : pas encore demandée"
        case .finderNotRunning: "Automatisation Finder : Finder n'est pas lancé"
        case .unknown: "Automatisation Finder : état inconnu"
        }
    }

    static func outcome(_ o: FinderOutcome?) -> String {
        guard let o else { return "" }
        switch o {
        case .cutMarked(let n): return "\(n) élément\(n > 1 ? "s" : "") coupé\(n > 1 ? "s" : "")"
        case .nothingSelected: return "Rien de sélectionné dans le Finder"
        case .moved(let n): return "\(n) élément\(n > 1 ? "s" : "") déplacé\(n > 1 ? "s" : "")"
        case .movedPartial(let m, let f): return "\(m) déplacé\(m > 1 ? "s" : ""), \(f) en échec"
        case .moveFailed(let f): return "Déplacement impossible (\(f) en échec)"
        case .imageSaved: return "Image enregistrée dans le dossier"
        case .imageFailed: return "Image non enregistrée"
        case .automationDenied: return "Automatisation du Finder refusée"
        case .scriptFailed: return "Le Finder n'a pas répondu"
        case .refused(let r):
            switch r {
            case .noItems: return "Rien à déplacer"
            case .destinationUnavailable: return "Dossier de destination indisponible"
            case .intoItself: return "Refusé : le dossier est dans l'élément déplacé"
            case .sameFolder: return "Déjà dans ce dossier"
            case .needsConfirmation(let n): return "Confirmer le déplacement de \(n) éléments"
            }
        }
    }
}
