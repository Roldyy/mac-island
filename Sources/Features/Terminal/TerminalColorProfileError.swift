import Foundation

/// Why a colour profile file was refused. Every message is French and says what to do.
enum TerminalColorProfileError: Error, Equatable, LocalizedError {
    case fileTooLarge
    case unsupportedType
    case unreadable
    case notAColorProfile
    case tooFewColors(found: Int)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Ce fichier dépasse 1 Mo : ce n’est pas un profil de couleurs."
        case .unsupportedType: "Type de fichier non pris en charge. Choisissez un fichier .terminal (Terminal) ou .itermcolors (iTerm2)."
        case .unreadable: "Impossible de lire ce fichier : il est vide, tronqué ou n’est pas un profil valide."
        case .notAColorProfile: "Ce fichier ne contient pas de profil de couleurs reconnu."
        case .tooFewColors(let found): "Profil refusé : \(found) couleur\(found > 1 ? "s" : "") valide\(found > 1 ? "s" : "") seulement, il en faut au moins 8."
        }
    }
}
