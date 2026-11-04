// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Mac Island calendar lane (Google Calendar through the macOS account). Hand-written, never touched by import.sh.
// Kept out of NotchCalendarStrings on purpose: that table is upstream's, one entry per language, trimmed after the patches.

import Foundation

struct CalendarAccountStrings {
    /// Title of the card shown while access is not granted, and its one-word button.
    let accessRequired: String
    let authorize: String
    /// The button that opens an event's video call, and what VoiceOver reads for it (`%@` is the event title).
    let join: String
    let joinLabel: String
    let declined: String
    let showDeclined: String
    let showDeclinedHint: String
    /// Empty state for a Mac with no Google account, and the way to add one.
    let googleTitle: String
    let googleHint: String
    let openAccounts: String
    /// Per-account shortcuts of the calendar list, and what VoiceOver reads for them (`%@` is the account).
    let selectAll: String
    let selectNone: String
    let selectAllLabel: String
    let selectNoneLabel: String

    static func strings(_ language: AppLanguage) -> CalendarAccountStrings {
        switch language {
        case .enUS: return CalendarAccountStrings(
            accessRequired: "Calendar access required",
            authorize: "Allow",
            join: "Join",
            joinLabel: "Join the video call: %@",
            declined: "Declined",
            showDeclined: "Show declined events",
            showDeclinedHint: "Declined events appear dimmed and never count down. Cancelled events stay hidden.",
            googleTitle: "Add your Google account in System Settings",
            googleHint: "In Internet Accounts, add Google and turn on Calendars for it. Its calendars then appear here.",
            openAccounts: "Open Internet Accounts",
            selectAll: "All",
            selectNone: "None",
            selectAllLabel: "Show every calendar of %@",
            selectNoneLabel: "Hide every calendar of %@")
        default: return CalendarAccountStrings(
            accessRequired: "Accès calendrier requis",
            authorize: "Autoriser",
            join: "Rejoindre",
            joinLabel: "Rejoindre la visioconférence : %@",
            declined: "Refusé",
            showDeclined: "Afficher les événements refusés",
            showDeclinedHint: "Les événements refusés apparaissent estompés et n’alimentent jamais le compte à rebours. Les événements annulés restent masqués.",
            googleTitle: "Ajoutez votre compte Google dans Réglages Système",
            googleHint: "Dans Comptes Internet, ajoutez Google puis activez Calendriers pour ce compte. Ses calendriers apparaissent alors ici.",
            openAccounts: "Ouvrir Comptes Internet",
            selectAll: "Tout",
            selectNone: "Aucun",
            selectAllLabel: "Afficher tous les calendriers de %@",
            selectNoneLabel: "Masquer tous les calendriers de %@")
        }
    }
}
