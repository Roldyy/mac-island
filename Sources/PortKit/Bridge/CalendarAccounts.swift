// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Mac Island calendar lane (Google Calendar through the macOS account). Hand-written, never touched by import.sh.

import AppKit
import EventKit
import Foundation

/// The kind of account behind a calendar. Google reaches EventKit as a CalDAV source titled "Gmail" or "Google",
/// once the account is added in System Settings > Internet Accounts with Calendars on.
enum CalendarSourceKind: String, Sendable, Equatable {
    case iCloud, google, exchange, calDAV, local, subscribed, birthdays, other

    static func classify(type: EKSourceType, title: String) -> CalendarSourceKind {
        let name = title.lowercased()
        switch type {
        case .mobileMe: return .iCloud
        case .calDAV:
            if name.contains("icloud") { return .iCloud }
            if name.contains("gmail") || name.contains("google") { return .google }
            return .calDAV
        case .exchange: return .exchange
        case .local: return .local
        case .subscribed: return .subscribed
        case .birthdays: return .birthdays
        @unknown default: return .other
        }
    }

    /// An SF Symbol for the account line of the picker.
    var symbol: String {
        switch self {
        case .iCloud: return "icloud"
        case .google: return "g.circle"
        case .exchange: return "building.2"
        case .calDAV, .other: return "person.crop.circle"
        case .local: return "desktopcomputer"
        case .subscribed: return "antenna.radiowaves.left.and.right"
        case .birthdays: return "gift"
        }
    }
}

/// One EKCalendar as plain values, so the tests never need an event store.
struct CalendarDescriptor: Sendable, Equatable {
    let id: String
    let title: String
    let color: NotchCalendarColor
    let sourceID: String
    let sourceTitle: String
    let sourceType: EKSourceType
}

protocol CalendarCatalogReading {
    func calendarDescriptors() -> [CalendarDescriptor]
}

/// The real store, walked source by source so that no account is missed. Used inside the calendar reader's actor.
struct EKCalendarCatalogReader: CalendarCatalogReading {
    let store: EKEventStore
    let tint: (EKCalendar) -> NotchCalendarColor

    func calendarDescriptors() -> [CalendarDescriptor] {
        var seen = Set<String>()
        var calendars: [EKCalendar] = []
        for source in store.sources {
            for calendar in source.calendars(for: .event) where seen.insert(calendar.calendarIdentifier).inserted {
                calendars.append(calendar)
            }
        }
        for calendar in store.calendars(for: .event) where seen.insert(calendar.calendarIdentifier).inserted {
            calendars.append(calendar)
        }
        return calendars.map {
            CalendarDescriptor(id: $0.calendarIdentifier, title: $0.title, color: tint($0),
                               sourceID: $0.source?.sourceIdentifier ?? "", sourceTitle: $0.source?.title ?? "",
                               sourceType: $0.source?.sourceType ?? .local)
        }
    }
}

enum CalendarCatalog {
    static func choices(from reader: some CalendarCatalogReading) -> [NotchCalendarChoice] {
        var seen = Set<String>()
        return reader.calendarDescriptors().compactMap { item in
            guard seen.insert(item.id).inserted else { return nil }
            return NotchCalendarChoice(
                id: item.id, title: CalendarText.clean(item.title, limit: 80),
                sourceID: item.sourceID, source: CalendarText.clean(item.sourceTitle, limit: 80),
                color: item.color, kind: .classify(type: item.sourceType, title: item.sourceTitle))
        }
    }
}

enum CalendarAccountSelection: Equatable { case all, some, none }

/// The island keeps what is left out, by EKCalendar identifier, under the key it always used: a calendar that
/// appears later starts shown, and nothing an earlier build stored is converted or lost.
enum CalendarSelection {
    static func setAccount(_ calendars: [NotchCalendarChoice], shown: Bool, excluded: Set<String>) -> Set<String> {
        let ids = Set(calendars.map(\.id))
        return shown ? excluded.subtracting(ids) : excluded.union(ids)
    }

    static func accountState(_ calendars: [NotchCalendarChoice], excluded: Set<String>) -> CalendarAccountSelection {
        let hidden = calendars.filter { excluded.contains($0.id) }.count
        return hidden == 0 ? .all : hidden == calendars.count ? .none : .some
    }

    /// Calendars that no longer exist are dropped. An empty catalog is a failed or early read, not an empty Mac.
    static func pruned(_ excluded: Set<String>, known: [NotchCalendarChoice]) -> Set<String> {
        guard !known.isEmpty else { return excluded }
        return excluded.intersection(known.map(\.id))
    }

    static func store(_ excluded: Set<String>, in defaults: UserDefaults = PortHost.defaults) {
        defaults.set(excluded.sorted(), forKey: DefaultsKey.notchCalendarExcluded)
    }
}

/// The empty-state card for a Mac that has no Google account yet.
enum CalendarAccountHint {
    /// Shown when the calendars read are only local, iCloud, subscribed or birthdays: no Google, Exchange or other
    /// CalDAV account. An empty read says nothing and shows nothing.
    static func needsGoogleAccount(_ choices: [NotchCalendarChoice]) -> Bool {
        !choices.isEmpty && !choices.contains { [.google, .exchange, .calDAV].contains($0.kind) }
    }

    /// The Internet Accounts pane of macOS 13+, then the older identifier.
    static let settingsURLs: [URL] = [
        "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
        "x-apple.systempreferences:com.apple.preferences.internetaccounts",
    ].compactMap(URL.init(string:))
}

enum CalendarAccessState: Equatable {
    case granted, notAsked, denied

    static func map(_ status: EKAuthorizationStatus) -> CalendarAccessState {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined, .writeOnly: return .notAsked
        default: return .denied
        }
    }
}
