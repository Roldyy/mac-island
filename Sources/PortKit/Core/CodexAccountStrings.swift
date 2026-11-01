// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// The Codex accounts the AI page gives limits cards of their own.
struct CodexAccountStrings {
    let title: String
    let explanation: String
    let accountName: String
    let remove: String
    let find: String
    let add: String
    let check: String
    let fallback: String
    let resetsNote: String
    let chooseFolder: String
    let invalidFolder: String
    /// On a card whose folder no longer passes the checks above.
    let folderProblem: String
    /// The name the usual `~/.codex` home gets.
    let defaultName: String
    let defaultAccount: String
    let refreshHint: String
    let signIn: String
    let update: String
    let failed: String
}

extension FeatureStrings {
    static func codexAccounts(_ language: AppLanguage) -> CodexAccountStrings {
        switch language {
        case .enUS: return CodexAccountStrings(
            title: "Codex accounts",
            explanation: "Each CODEX_HOME folder you add gets its own limits card. While the AI Agents page is open, Codex checks each one about every five minutes with that folder’s own sign-in. No prompt is sent.",
            accountName: "Account name",
            remove: "Remove this account’s card",
            find: "Find local accounts",
            add: "Add folder…",
            check: "Check limits",
            fallback: "With no accounts added, Codex limits come from its local sessions.",
            resetsNote: "The Resets card still belongs to the default Codex account.",
            chooseFolder: "Choose a Codex folder",
            invalidFolder: "Choose a separate CODEX_HOME folder with config.toml or auth.json in it. The folder must be yours and not writable by others, and auth.json must be private and not a link. Codex may refresh its own sign-in and caches there.",
            folderProblem: "Choose this account’s folder again in Settings.",
            defaultName: "Default",
            defaultAccount: "Default account",
            refreshHint: "Refresh to check this account’s limits.",
            signIn: "Sign in with ChatGPT in this Codex folder.",
            update: "Update Codex to check limits.",
            failed: "Could not check limits. Try again.")
        default: return CodexAccountStrings(
            title: "Comptes Codex",
            explanation: "Chaque dossier CODEX_HOME ajouté a sa propre carte de limites. Tant que la page Agents IA est ouverte, Codex vérifie chacun environ toutes les cinq minutes, avec la connexion de ce dossier. Aucune requête n’est envoyée.",
            accountName: "Nom du compte",
            remove: "Retirer la carte de ce compte",
            find: "Chercher les comptes locaux",
            add: "Ajouter un dossier…",
            check: "Vérifier les limites",
            fallback: "Sans compte ajouté, les limites de Codex proviennent de ses sessions locales.",
            resetsNote: "La carte Réinitialisations reste celle du compte Codex par défaut.",
            chooseFolder: "Choisissez un dossier Codex",
            invalidFolder: "Choisissez un dossier CODEX_HOME distinct contenant config.toml ou auth.json. Le dossier doit vous appartenir et ne pas être modifiable par d’autres, et auth.json doit être privé et ne pas être un lien. Codex peut y renouveler sa propre connexion et ses caches.",
            folderProblem: "Choisissez à nouveau le dossier de ce compte dans les Réglages.",
            defaultName: "Par défaut",
            defaultAccount: "Compte par défaut",
            refreshHint: "Actualisez pour vérifier les limites de ce compte.",
            signIn: "Connectez-vous avec ChatGPT dans ce dossier Codex.",
            update: "Mettez Codex à jour pour vérifier les limites.",
            failed: "Impossible de vérifier les limites. Réessayez.")
        }
    }
}
