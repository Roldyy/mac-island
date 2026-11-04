// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import Combine
import EventKit

/// EventKit objects stay on one actor; only immutable display values reach UI.
private actor NotchCalendarReader {
    private lazy var store = EKEventStore()

    func read(interval: DateInterval, excluded: Set<String>, showDeclined: Bool) -> [NotchCalendarEvent] {
        guard !Task.isCancelled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendars = NotchCalendarSupport.calendarsToRead(store.calendars(for: .event), excluded: excluded,
                                                             identifier: \.calendarIdentifier)
        if calendars?.isEmpty == true { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            let declined = event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) == true
            guard let facts = CalendarEventFacts.make(
                    CalendarEventRaw(title: event.title, location: event.location, notes: event.notes, url: event.url,
                                     cancelled: event.status == .canceled, currentUserDeclined: declined),
                    showDeclined: showDeclined),
                  let identifier = event.eventIdentifier,
                  let start = event.startDate, let end = event.endDate else { return nil }
            let recurring = event.hasRecurrenceRules || event.isDetached
            let countdownKey = NotchCalendarSupport.countdownKey(
                identifier: identifier, occurrence: recurring ? event.occurrenceDate ?? start : nil)
            return NotchCalendarEvent(id: identifier + ":" + String(start.timeIntervalSinceReferenceDate),
                                      title: facts.title, calendar: CalendarText.clean(event.calendar.title, limit: 80),
                                      start: start, end: end, allDay: event.isAllDay,
                                      location: facts.location, color: Self.tint(event.calendar),
                                      calendarItemIdentifier: event.calendarItemIdentifier,
                                      recurring: recurring, countdownKey: countdownKey,
                                      declined: facts.declined, joinURL: facts.joinURL)
        }
    }

    func calendars() -> [NotchCalendarChoice] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return CalendarCatalog.choices(from: EKCalendarCatalogReader(store: store, tint: Self.tint))
    }

    private static func tint(_ calendar: EKCalendar) -> NotchCalendarColor {
        let color = calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        return color.map { NotchCalendarColor(red: $0.redComponent, green: $0.greenComponent,
                                              blue: $0.blueComponent) } ?? .fallback
    }
}

/// Owned by the notch lifecycle, including sleep and lock. No event text is
/// persisted; events chosen for the countdown are kept by identifier only.
final class NotchCalendarService: NSObject, ObservableObject {
    static let shared = NotchCalendarService()
    @Published private(set) var events: [NotchCalendarEvent] = []
    @Published private(set) var countdown: NotchCalendarCountdown?
    @Published private(set) var loading = false
    /// True when the calendars read are only local, iCloud, subscribed or birthdays: the island then offers the
    /// way to add a Google account in System Settings.
    @Published private(set) var needsGoogleAccount = false
    /// The event the Calendar page scrolls to once, after a click on the countdown.
    @Published var revealing: String?
    /// Countdown keys of the events chosen from their menu.
    @Published private(set) var chosenCountdowns = Set<String>()
    private var reader: NotchCalendarReader?
    private var task: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var refreshObserver: CalendarRefreshObserver?
    private var permissionSubscription: AnyCancellable?
    private var generation = UUID()
    private var visibleMonth: Date?
    private var countdownEnabled = false
    private var timeLeftEnabled = false
    private var excludedCalendars = Set<String>()
    private var showDeclined = false

    private override init() { super.init() }

    /// Every event calendar on this Mac, for the Settings list. Works while
    /// the island's reader is stopped, since the list is edited from Settings.
    func calendarChoices() async -> [NotchCalendarChoice] {
        await (reader ?? NotchCalendarReader()).calendars()
    }

    func isChosen(_ event: NotchCalendarEvent) -> Bool {
        NotchCalendarSupport.isChosen(event, in: chosenCountdowns)
    }

    /// Counts down to one event, or stops, whatever the countdown for every event does.
    func setCountdown(_ chosen: Bool, for event: NotchCalendarEvent) {
        NotchCalendarSupport.setCountdown(chosen, for: event)
        let keys = Set(NotchCalendarSupport.chosenCountdowns().keys)
        guard keys != chosenCountdowns else { return }
        chosenCountdowns = keys
        if let countdown, !follows(countdown) { self.countdown = nil }
        refresh()
    }

    private func follows(_ countdown: NotchCalendarCountdown) -> Bool {
        countdown.ongoing ? timeLeftEnabled : countdownEnabled || isChosen(countdown.event)
    }

    func showMonth(_ month: Date?) {
        visibleMonth = month
        events = []
        refresh()
    }

    func syncWithPreferences() {
        guard NotchCalendarSupport.isEnabled() else { stop(); return }
        let countdownEnabled = NotchCalendarSupport.showsCountdown()
        let timeLeftEnabled = NotchCalendarSupport.showsTimeLeft()
        let excludedCalendars = NotchCalendarSupport.excludedCalendars()
        let showDeclined = CalendarEventFacts.showsDeclined()
        let chosenCountdowns = Set(NotchCalendarSupport.chosenCountdowns().keys)
        guard reader == nil else {
            if self.countdownEnabled != countdownEnabled || self.timeLeftEnabled != timeLeftEnabled
                || self.excludedCalendars != excludedCalendars || self.chosenCountdowns != chosenCountdowns
                || self.showDeclined != showDeclined {
                if !excludedCalendars.isSubset(of: self.excludedCalendars) || self.showDeclined != showDeclined {
                    events = []
                    countdown = nil
                }
                self.showDeclined = showDeclined
                self.countdownEnabled = countdownEnabled
                self.timeLeftEnabled = timeLeftEnabled
                self.excludedCalendars = excludedCalendars
                if self.chosenCountdowns != chosenCountdowns { self.chosenCountdowns = chosenCountdowns }
                if let countdown, !follows(countdown) { self.countdown = nil }
                refresh()
            }
            return
        }
        self.countdownEnabled = countdownEnabled
        self.timeLeftEnabled = timeLeftEnabled
        self.excludedCalendars = excludedCalendars
        self.showDeclined = showDeclined
        if self.chosenCountdowns != chosenCountdowns { self.chosenCountdowns = chosenCountdowns }
        reader = NotchCalendarReader()
        // Pushed by EventKit (a Google sync is a store change), by a wake and by the clock: never a fast poll.
        refreshObserver = CalendarRefreshObserver { [weak self] in self?.refresh() }
        refreshObserver?.start()
        permissionSubscription = Permissions.shared.$calendarAccess.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        task?.cancel()
        refreshTimer?.invalidate(); refreshTimer = nil
        generation = UUID()
        guard NotchCalendarSupport.isEnabled(), let reader else { stop(); return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            events = []; countdown = nil; loading = false; needsGoogleAccount = false
            return
        }
        let requested = generation
        let now = Date()
        let interval = NotchCalendarSupport.readInterval(month: visibleMonth, now: now)
        let currentInterval = NotchCalendarSupport.readInterval(month: nil, now: now)
        let needsCurrentRead = NotchCalendarSupport.needsCurrentRead(
            visible: interval, current: currentInterval,
            countdownEnabled: countdownEnabled || timeLeftEnabled || !chosenCountdowns.isEmpty)
        let excluded = excludedCalendars
        let showDeclined = showDeclined
        loading = events.isEmpty
        task = Task { @MainActor [weak self] in
            let result = await reader.read(interval: interval, excluded: excluded, showDeclined: showDeclined)
            let currentResult = needsCurrentRead
                ? await reader.read(interval: currentInterval, excluded: excluded, showDeclined: showDeclined) : result
            let known = await reader.calendars()
            guard !Task.isCancelled, let self, self.generation == requested,
                  NotchCalendarSupport.isEnabled() else { return }
            let now = Date()
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                self.events = []; self.countdown = nil; self.loading = false; self.task = nil
                self.needsGoogleAccount = false
                return
            }
            self.needsGoogleAccount = CalendarAccountHint.needsGoogleAccount(known)
            // A calendar that vanished (account removed) leaves the stored selection quietly.
            let pruned = CalendarSelection.pruned(self.excludedCalendars, known: known)
            if pruned != self.excludedCalendars {
                CalendarSelection.store(pruned)
                self.excludedCalendars = pruned
            }
            self.events = NotchCalendarSupport.ordered(result)
            let currentEvents = needsCurrentRead ? NotchCalendarSupport.ordered(currentResult) : self.events
            self.updateChosenCountdowns(currentEvents, now: now)
            self.countdown = NotchCalendarSupport.countdown(currentEvents, now: now, starts: self.countdownEnabled,
                                                            ends: self.timeLeftEnabled, chosen: self.chosenCountdowns)
            self.loading = false
            self.task = nil
            let agendaRefresh = NotchCalendarSupport.nextRefresh(self.events, now: now)
            let countdownRefresh = NotchCalendarSupport.countdownTransition(
                currentEvents, now: now, starts: self.countdownEnabled, ends: self.timeLeftEnabled,
                chosen: self.chosenCountdowns)
            let nextRefresh = min(agendaRefresh, countdownRefresh ?? agendaRefresh)
            let timer = Timer(fireAt: nextRefresh,
                              interval: 0, target: self, selector: #selector(self.timedRefresh),
                              userInfo: nil, repeats: false)
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.refreshTimer = timer
        }
    }

    @objc private func timedRefresh() { refresh() }

    /// A chosen event read again keeps its current end, and one that has
    /// ended is forgotten. Only the week holding every countdown the island
    /// can show is read; a choice further ahead keeps its end until then.
    private func updateChosenCountdowns(_ events: [NotchCalendarEvent], now: Date) {
        guard !chosenCountdowns.isEmpty,
              let choices = NotchCalendarSupport.refreshedChoices(NotchCalendarSupport.chosenCountdowns(),
                                                                  events: events, now: now) else { return }
        NotchCalendarSupport.storeChosenCountdowns(choices)
        let keys = Set(choices.keys)
        if keys != chosenCountdowns { chosenCountdowns = keys }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        refreshTimer?.invalidate(); refreshTimer = nil
        refreshObserver?.stop()
        refreshObserver = nil
        permissionSubscription = nil
        reader = nil
        visibleMonth = nil
        countdownEnabled = false
        timeLeftEnabled = false
        excludedCalendars = []
        showDeclined = false
        if !chosenCountdowns.isEmpty { chosenCountdowns = [] }
        events = []; countdown = nil; loading = false; needsGoogleAccount = false
    }
}
