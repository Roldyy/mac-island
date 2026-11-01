// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchMusicExtrasStrings {
    let lyrics: String
    let lyricsDescription: String
    let enableLyrics: String
    let online: String
    let onlineHint: String
    let importLyrics: String
    let importHint: String
    let loading: String
    let unavailable: String
    let failed: String
    let retry: String
    let instrumental: String
    let waiting: String
    let noPosition: String
    let offset: String
    let earlier: String
    let later: String
    let reset: String
    let actionFailed: String
    let playbackFailed: String
    let allowPlayback: String
    let automationPermission: String
    let automationExplanation: String
    let queue: String
    let queueDescription: String
    let enableQueue: String
    let queueUnavailable: String
    let queueEmpty: String
    let playNow: String
    let refresh: String
    let openPlayer: String
    let playbackSource: String
    let automaticSource: String
    let includeOtherPlayers: String
    let liveEqualizer: String
    /// One line for the features hub, where the hint below would not fit.
    let liveEqualizerDescription: String
    let liveEqualizerHint: String
    let liveEqualizerUnavailable: String
    let shuffle: String
    let preferredPlayer: String
    let preferredPlayerHint: String
    /// "Open Spotify", with the app's name in place of %@.
    let openNamedPlayer: String
    let browserCovers: String
    let browserCoversHint: String
}

extension FeatureStrings {
    static func notchMusicExtras(_ language: AppLanguage) -> NotchMusicExtrasStrings {
        switch language {
        case .enUS: return NotchMusicExtrasStrings(
            lyrics: "Lyrics",
            lyricsDescription: "Follow the lyrics of the current song in the Dynamic Island.",
            enableLyrics: "Show lyrics",
            online: "Find lyrics online",
            onlineHint: "While lyrics are open, send the song title, artist, album and duration to lrclib.net. Imported lyrics stay on this Mac. Song titles, artist names and albums may also be checked with musicbrainz.org.",
            importLyrics: "Import lyrics…",
            importHint: "Choose timed lyrics for the current recording. They are kept only while this song is open.",
            loading: "Loading lyrics…",
            unavailable: "No matching lyrics for this recording.",
            failed: "Could not load the lyrics.",
            retry: "Try again",
            instrumental: "Instrumental",
            waiting: "Waiting for the first verse",
            noPosition: "The player does not share its position.",
            offset: "Timing",
            earlier: "Earlier",
            later: "Later",
            reset: "Reset",
            actionFailed: "The player did not switch to this song.",
            playbackFailed: "Could not change playback.",
            allowPlayback: "Allow playback control",
            automationPermission: "Playback automation",
            automationExplanation: "Some music apps require permission for their playback controls. Authorize the selected player from Dynamic Island; access is granted separately for each app.",
            queue: "Up next",
            queueDescription: "See the actual upcoming songs shared by your player.",
            enableQueue: "Show upcoming songs",
            queueUnavailable: "This player does not share its upcoming songs.",
            queueEmpty: "No upcoming songs",
            playNow: "Play now",
            refresh: "Refresh",
            openPlayer: "Open player",
            playbackSource: "Playback source",
            automaticSource: "Automatic",
            includeOtherPlayers: "Automatically include videos and other apps",
            liveEqualizer: "Bars follow the music",
            liveEqualizerDescription: "Move the Dynamic Island bars with the sound your player makes.",
            liveEqualizerHint: "Listens to the player’s own audio output to move the bars. macOS asks once to allow system audio recording. Nothing is stored or sent. Without it, the bars keep their usual motion.",
            liveEqualizerUnavailable: "Needs macOS 14.4 or later.",
            shuffle: "Shuffle",
            preferredPlayer: "Open when nothing is playing",
            preferredPlayerHint: "The cover and the playback buttons open this app. Automatic opens the music app that played last, then Spotify or Apple Music.",
            openNamedPlayer: "Open %@",
            browserCovers: "Find covers for Firefox and Zen",
            browserCoversHint: "When Firefox, Zen or another Firefox-based browser plays without a sharp cover, read its saved session on this Mac to find the song’s YouTube tab and load its thumbnail from i.ytimg.com. If no tab shows the song but a YouTube Music tab is open, send the song title, artist and region to itunes.apple.com and load the album art from mzstatic.com.")
        default: return NotchMusicExtrasStrings(
            lyrics: "Paroles",
            lyricsDescription: "Suivez les paroles du morceau en cours dans le Dynamic Island.",
            enableLyrics: "Afficher les paroles",
            online: "Chercher les paroles en ligne",
            onlineHint: "Lorsque les paroles sont ouvertes, le titre, l’artiste, l’album et la durée sont envoyés à lrclib.net. Les paroles importées restent sur ce Mac. Les titres de chansons et les noms d’artistes et d’albums peuvent aussi être vérifiés sur musicbrainz.org.",
            importLyrics: "Importer des paroles…",
            importHint: "Choisissez les paroles synchronisées de cet enregistrement. Elles restent disponibles uniquement tant que ce morceau est ouvert.",
            loading: "Chargement des paroles…",
            unavailable: "Aucune parole correspondante pour cet enregistrement.",
            failed: "Impossible de charger les paroles.",
            retry: "Réessayer",
            instrumental: "Instrumental",
            waiting: "En attente du premier couplet",
            noPosition: "Le lecteur ne partage pas la position de lecture.",
            offset: "Synchronisation",
            earlier: "Avancer",
            later: "Retarder",
            reset: "Réinitialiser",
            actionFailed: "Le lecteur n’a pas lancé ce morceau.",
            playbackFailed: "Impossible de modifier la lecture.",
            allowPlayback: "Autoriser le contrôle de la lecture",
            automationPermission: "Automatisation de la lecture",
            automationExplanation: "Certains lecteurs demandent une autorisation pour leurs commandes. Autorisez le lecteur choisi dans Dynamic Island ; chaque app reçoit une autorisation distincte.",
            queue: "À suivre",
            queueDescription: "Consultez les prochains morceaux partagés par votre lecteur.",
            enableQueue: "Afficher les prochains morceaux",
            queueUnavailable: "Ce lecteur ne partage pas ses prochains morceaux.",
            queueEmpty: "Aucun morceau à suivre",
            playNow: "Lire maintenant",
            refresh: "Actualiser",
            openPlayer: "Ouvrir le lecteur",
            playbackSource: "Source de lecture",
            automaticSource: "Automatique",
            includeOtherPlayers: "Inclure automatiquement les vidéos et les autres apps",
            liveEqualizer: "Les barres suivent la musique",
            liveEqualizerDescription: "Animez les barres du Dynamic Island avec le son de votre lecteur.",
            liveEqualizerHint: "Écoute la sortie audio du lecteur pour animer les barres. macOS demande une fois l’autorisation d’enregistrer l’audio du système. Rien n’est conservé ni envoyé. Sans elle, les barres gardent leur mouvement habituel.",
            liveEqualizerUnavailable: "Nécessite macOS 14.4 ou ultérieur.",
            shuffle: "Lecture aléatoire",
            preferredPlayer: "Ouvrir quand rien ne joue",
            preferredPlayerHint: "La pochette et les boutons de lecture ouvrent cette app. Automatique ouvre la dernière app de musique utilisée, puis Spotify ou Apple Music.",
            openNamedPlayer: "Ouvrir %@",
            browserCovers: "Chercher les pochettes pour Firefox et Zen",
            browserCoversHint: "Quand Firefox, Zen ou un autre navigateur basé sur Firefox lit un morceau sans pochette nette, sa session enregistrée est lue sur ce Mac pour trouver l’onglet YouTube du morceau et charger sa miniature depuis i.ytimg.com. Si aucun onglet n’affiche le morceau mais qu’un onglet YouTube Music est ouvert, le titre, l’artiste et la région sont envoyés à itunes.apple.com et la pochette de l’album est chargée depuis mzstatic.com.")
        }
    }
}
