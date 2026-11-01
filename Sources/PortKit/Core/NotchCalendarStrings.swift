// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchCalendarStrings {
    let title: String
    let description: String
    let permission: String
    let allow: String
    let denied: String
    let settings: String
    let empty: String
    let next: String
    let ongoing: String
    let allDay: String
    let untitled: String
    let openCalendar: String
    let week: String
    let today: String
    let requestFailed: String
    let previousMonth: String
    let nextMonth: String
    let previousWeek: String
    let nextWeek: String
    /// The month grid, offered from the week strip of a short island.
    let month: String
    let emptyDay: String
    let hasEvents: String
    let countdown: String
    let countdownHint: String
    /// An event's menu in the island, to count down to that event alone.
    let addCountdown: String
    let removeCountdown: String
    /// Counts the event under way down to its end.
    let timeLeft: String
    let timeLeftHint: String
    /// Numbers each week of the month grid, as Calendar can.
    let weekNumbers: String
    /// Read out for each of those numbers, which the grid shows bare.
    let weekNumber: String
    /// Heads the per-calendar checkboxes in Settings.
    let calendars: String
}

extension FeatureStrings {
    static func notchCalendar(_ language: AppLanguage) -> NotchCalendarStrings {
        switch language {
        case .enUS: return NotchCalendarStrings(
            title: "Calendar",
            description: "Browse the month and your upcoming appointments in the Dynamic Island.",
            permission: "Read your calendars to show upcoming appointments. Events stay on this Mac.",
            allow: "Allow Calendar Access",
            denied: "Allow calendar access in System Settings to see your appointments.",
            settings: "Open System Settings",
            empty: "No upcoming appointments",
            next: "Up next",
            ongoing: "Happening now",
            allDay: "All day",
            untitled: "Untitled event",
            openCalendar: "Open Calendar",
            week: "Next 7 days",
            today: "Today",
            requestFailed: "Could not request calendar access. Please try again.",
            previousMonth: "Previous month",
            nextMonth: "Next month",
            previousWeek: "Previous week",
            nextWeek: "Next week",
            month: "Month",
            emptyDay: "No appointments on this day",
            hasEvents: "Has appointments",
            countdown: "Event countdown",
            countdownHint: "Show every timed event in the closed island during the hour before it starts. To count down to only some, turn this off and right-click them on the island’s Calendar page. Titles may appear in screen captures.",
            addCountdown: "Add Countdown",
            removeCountdown: "Remove Countdown",
            timeLeft: "Time left in current event",
            timeLeftHint: "Show a timed event in progress in the closed island during the hour before it ends. Its title may appear in screen captures.",
            weekNumbers: "Week numbers",
            weekNumber: "Week %d",
            calendars: "Calendars shown")
        default: return NotchCalendarStrings(
            title: "Calendrier",
            description: "Consultez le mois et vos prochains rendez-vous dans le Dynamic Island.",
            permission: "Lit vos calendriers pour afficher les prochains rendez-vous. Les événements restent sur ce Mac.",
            allow: "Autoriser l’accès au calendrier",
            denied: "Autorisez l’accès au calendrier dans les Réglages Système pour voir vos rendez-vous.",
            settings: "Ouvrir les Réglages Système",
            empty: "Aucun rendez-vous à venir",
            next: "À venir",
            ongoing: "En cours",
            allDay: "Toute la journée",
            untitled: "Événement sans titre",
            openCalendar: "Ouvrir Calendrier",
            week: "7 prochains jours",
            today: "Aujourd’hui",
            requestFailed: "Impossible de demander l’accès au calendrier. Réessayez.",
            previousMonth: "Mois précédent",
            nextMonth: "Mois suivant",
            previousWeek: "Semaine précédente",
            nextWeek: "Semaine suivante",
            month: "Mois",
            emptyDay: "Aucun rendez-vous ce jour-là",
            hasEvents: "Rendez-vous prévus",
            countdown: "Compte à rebours du prochain événement",
            countdownHint: "Affiche chaque événement avec une heure dans l’encoche pendant l’heure qui précède. Pour n’en décompter que certains, désactivez cette option et faites un clic droit sur eux dans la page Calendrier de l’encoche. Les titres peuvent apparaître dans les captures d’écran.",
            addCountdown: "Ajouter un compte à rebours",
            removeCountdown: "Retirer le compte à rebours",
            timeLeft: "Temps restant de l’événement en cours",
            timeLeftHint: "Affiche l’événement en cours avec une heure dans l’encoche pendant l’heure qui précède sa fin. Son titre peut apparaître dans les captures d’écran.",
            weekNumbers: "Numéros de semaine",
            weekNumber: "Semaine %d",
            calendars: "Calendriers affichés")
        }
    }
}
