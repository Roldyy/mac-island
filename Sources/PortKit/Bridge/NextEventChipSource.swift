// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import AppKit
import Combine
import Foundation
import ShellKit

/// Pure part of the "Prochain rendez-vous" chip.
enum NextEventChip {
    static let titleLimit = 24

    /// The first timed, not declined event that starts later today. Nil when there is none: an event already under
    /// way, one tomorrow or an all-day one is not "the next appointment".
    static func select(_ events: [NotchCalendarEvent], now: Date, calendar: Calendar = .current) -> NotchCalendarEvent? {
        NotchCalendarSupport.ordered(events).first {
            !$0.allDay && !$0.declined && $0.start > now && calendar.isDate($0.start, inSameDayAs: now)
        }
    }

    /// "Point hebdo dans 12 min".
    static func primary(for event: NotchCalendarEvent, now: Date) -> String {
        let title = StatusChipBridgeFormat.truncated(event.title, limit: titleLimit)
        return "\(title.isEmpty ? "Rendez-vous" : title) \(StatusChipBridgeFormat.countdown(until: event.start, now: now))"
    }

    /// Seconds until the text of the chip changes (the minute rolls over), at least a second.
    static func secondsUntilTextChanges(for event: NotchCalendarEvent, now: Date) -> TimeInterval {
        let remaining = event.start.timeIntervalSince(now)
        guard remaining > 0 else { return 1 }
        let minutes = Double(StatusChipBridgeFormat.minutesLeft(until: event.start, now: now))
        return max(1, remaining - (minutes - 1) * 60 + 0.5)
    }

    /// "Rejoindre" only for a link that passes `CalendarConferenceLink.validated`, checked again when the button is
    /// pressed; "Ouvrir le calendrier" always.
    static func actions(for event: NotchCalendarEvent, openURL: @escaping @MainActor (URL) -> Void,
                        openCalendar: @escaping @MainActor () -> Void) -> [StatusChipAction] {
        var actions: [StatusChipAction] = []
        if let link = event.joinURL.flatMap(CalendarConferenceLink.validated) {
            actions.append(StatusChipAction(id: "join", title: "Rejoindre", systemImage: "video") {
                if let checked = CalendarConferenceLink.validated(link) { openURL(checked) }
            })
        }
        actions.append(StatusChipAction(id: "calendar", title: "Ouvrir le calendrier", systemImage: "calendar",
                                        handler: openCalendar))
        return actions
    }

    static func reading(for event: NotchCalendarEvent, now: Date, openURL: @escaping @MainActor (URL) -> Void,
                        openCalendar: @escaping @MainActor () -> Void) -> StatusChipReading {
        StatusChipReading(kind: .nextEvent, primary: primary(for: event, now: now),
                          actions: actions(for: event, openURL: openURL, openCalendar: openCalendar))
    }
}

/// "Prochain rendez-vous": observes `NotchCalendarService`, never drives it.
///
/// The service is started by the Calendar feature (its binding calls `syncWithPreferences()`), and that is the only
/// EventKit consumer: this chip subscribes to `$events` while started and reads nothing else, so with the feature
/// off, without calendar access or without an event today there is no reading and no chip. The access prompt belongs
/// to the Calendar tab, never to this chip. One wake-up at the next minute roll-over while a chip shows; nothing
/// otherwise, and nothing after `stop()`.
@MainActor
final class NextEventChipSource: StatusChipBridgeSource {
    struct Hooks {
        /// Calls `deliver` with the service's events each time they change (and once when subscribed).
        var watch: @MainActor (_ deliver: @escaping @MainActor ([NotchCalendarEvent]) -> Void) -> AnyCancellable?
        var now: @MainActor () -> Date
        var sleep: @Sendable (Duration) async throws -> Void
        var openURL: @MainActor (URL) -> Void
        var openCalendar: @MainActor () -> Void

        @MainActor static func live(navigator: StatusChipNavigator? = nil) -> Hooks {
            let navigator = navigator ?? .live
            return Hooks(
                watch: { deliver in
                    NotchCalendarService.shared.$events.receive(on: DispatchQueue.main)
                        .sink { events in MainActor.assumeIsolated { deliver(events) } }
                },
                now: { Date() },
                sleep: StatusChipBridgeSource.sleeper(tolerance: .seconds(1)),
                openURL: { NSWorkspace.shared.open($0) },
                openCalendar: {
                    if navigator.isAvailable() {
                        navigator.open("calendar")
                    } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                    }
                })
        }
    }

    private let hooks: Hooks
    private var subscription: AnyCancellable?
    private var wake: Task<Void, Never>?
    private var events: [NotchCalendarEvent] = []

    init(hooks: Hooks? = nil) {
        self.hooks = hooks ?? .live()
        super.init(kind: .nextEvent)
    }

    override func begin() {
        subscription = hooks.watch { [weak self] events in
            guard let self, self.isRunning else { return }
            self.events = events
            self.refresh()
        }
    }

    override func end() {
        subscription = nil
        wake?.cancel()
        wake = nil
        events = []
    }

    func refresh() {
        wake?.cancel()
        wake = nil
        let now = hooks.now()
        guard let event = NextEventChip.select(events, now: now) else { publish(nil); return }
        publish(NextEventChip.reading(for: event, now: now, openURL: hooks.openURL, openCalendar: hooks.openCalendar))
        let delay = NextEventChip.secondsUntilTextChanges(for: event, now: now)
        let sleep = hooks.sleep
        wake = Task { [weak self] in
            do { try await sleep(.seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
