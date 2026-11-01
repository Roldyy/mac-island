// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W8B (timer, Pomodoro, stopwatch, alarm, calendar, accessories, mirrored notifications). The lane owns this file.

import AppKit
import Combine
import IslandKit
import IslandUI
import SwiftUI

// MARK: - Closed island, pure

/// What the timer is doing, as plain numbers. Built from `NotchTimerSession` and the service clock.
struct TimerReading: Equatable {
    var mode: NotchTimerMode
    var phase: NotchTimerPhase
    /// Seconds left in a countdown, elapsed on a stopwatch.
    var seconds: TimeInterval
    var duration: TimeInterval
    var isRunning: Bool
    var isPaused: Bool
    var completed: Bool

    init(mode: NotchTimerMode, phase: NotchTimerPhase, seconds: TimeInterval, duration: TimeInterval,
         isRunning: Bool, isPaused: Bool, completed: Bool = false) {
        self.mode = mode
        self.phase = phase
        self.seconds = seconds
        self.duration = duration
        self.isRunning = isRunning
        self.isPaused = isPaused
        self.completed = completed
    }

    init?(session: NotchTimerSession, now: TimeInterval) {
        guard session.hasSession else { return nil }
        self.init(mode: session.mode, phase: session.phase, seconds: session.reading(at: now), duration: session.duration,
                  isRunning: session.isRunning, isPaused: session.isPaused, completed: session.completed)
    }
}

/// The running timer as an indicator of the closed island. Pure.
///
/// Not a Settings channel of `AmbientChannel` (that list is the user's switchboard of the other lanes): the switch
/// lives with the feature, in the timer tab, under the key `notchIdleShowTimer`, which is exactly the key a future
/// `timer` channel would use. Off by default, so a running timer shows nothing in the closed island until asked.
/// A finished timer is a different thing: a short alert (`IslandNoticeMapper`).
enum TimerIndicator {
    static let id = "timer"
    static let switchKey = "notchIdleShowTimer"

    static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    static func symbol(_ reading: TimerReading) -> String {
        if reading.isPaused { return "pause.fill" }
        switch reading.phase {
        case .timer: return "timer"
        case .focus: return "target"
        case .shortBreak, .longBreak: return "cup.and.saucer"
        case .stopwatch: return "stopwatch"
        }
    }

    static func phaseWord(_ reading: TimerReading) -> String {
        switch reading.phase {
        case .timer: "Minuteur"
        case .focus: "Pomodoro, concentration"
        case .shortBreak: "Pomodoro, courte pause"
        case .longBreak: "Pomodoro, longue pause"
        case .stopwatch: "Chronomètre"
        }
    }

    static func indicator(_ reading: TimerReading?) -> AmbientIndicator? {
        guard let reading, !reading.completed else { return nil }
        let text = clockText(reading.seconds)
        let progress: Double? = reading.mode == .stopwatch || reading.duration <= 0 ? nil
            : min(1, max(0, 1 - reading.seconds / reading.duration))
        return AmbientIndicator(
            id: id, channel: id, symbol: symbol(reading), text: text, status: reading.isPaused ? .warning : .neutral,
            progress: progress, priority: .ambient, wing: .trailing,
            label: "\(phaseWord(reading)) : \(text)\(reading.isPaused ? ", en pause" : "")")
    }
}

/// The next appointment as an indicator, during the hour before it (or until it ends once it began). Pure.
enum CalendarIndicator {
    static let id = "calendar"
    static let switchKey = "notchIdleShowCalendar"

    static func indicator(title: String, target: Date, ongoing: Bool, now: Date) -> AmbientIndicator? {
        guard target > now else { return nil }
        let text = NotchCalendarSupport.countdownText(until: target, now: now)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return AmbientIndicator(
            id: id, channel: id, symbol: "calendar", text: text, status: ongoing ? .info : .neutral,
            priority: .ambient, wing: .trailing,
            label: "\(ongoing ? "Fin de" : "Début de") \(name.isEmpty ? "l’événement" : name) dans \(text)")
    }
}

/// Keeps one closed-island indicator in step with a reading that moves every second, and only while the user's switch
/// is on and there is something to show. One second tick while it is up, nothing otherwise.
@MainActor
final class ClosedIslandTicker {
    struct Hooks {
        var isOn: () -> Bool
        var make: (Date) -> AmbientIndicator?
        var post: (AmbientIndicator) -> Void
        var withdraw: (String) -> Void
        var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        var now: () -> Date = { Date() }
    }

    private let id: String
    private let hooks: Hooks
    private var tick: Task<Void, Never>?

    init(id: String, hooks: Hooks) {
        self.id = id
        self.hooks = hooks
    }

    var isTicking: Bool { tick != nil }

    func refresh() {
        tick?.cancel()
        tick = nil
        let date = hooks.now()
        guard hooks.isOn(), let indicator = hooks.make(date) else {
            hooks.withdraw(id)
            return
        }
        hooks.post(indicator)
        let sleep = hooks.sleep
        tick = Task { [weak self] in
            do { try await sleep(.seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func stop() {
        tick?.cancel()
        tick = nil
        hooks.withdraw(id)
    }
}

// MARK: - Lane

/// Everything the lane does to the ported services and to the island. The registry tests swap it for a recorder.
struct TimerRuntime {
    var syncTimer: @MainActor () -> Void
    var stopTimer: @MainActor () -> Void
    var syncCalendar: @MainActor () -> Void
    var stopCalendar: @MainActor () -> Void
    var syncNotifications: @MainActor () -> Void
    var stopNotifications: @MainActor () -> Void
    var syncAccessories: @MainActor () -> Void
    var stopAccessories: @MainActor () -> Void
    /// Refreshes the closed-island timer / calendar indicator whenever the service moves (live: Combine sinks).
    var watchTimer: @MainActor (_ refresh: @escaping @MainActor () -> Void) -> AnyCancellable?
    var watchCalendar: @MainActor (_ refresh: @escaping @MainActor () -> Void) -> AnyCancellable?
    var timerTicker: @MainActor () -> ClosedIslandTicker
    var calendarTicker: @MainActor () -> ClosedIslandTicker

    static let live = TimerRuntime(
        syncTimer: { NotchTimerService.shared.syncWithPreferences() },
        stopTimer: { NotchTimerService.shared.stop() },
        syncCalendar: { NotchCalendarService.shared.syncWithPreferences() },
        stopCalendar: { NotchCalendarService.shared.stop() },
        syncNotifications: { NotchNotificationService.shared.syncWithPreferences() },
        stopNotifications: { NotchNotificationService.shared.stop() },
        syncAccessories: { NotchAccessoryService.shared.syncWithPreferences() },
        stopAccessories: { NotchAccessoryService.shared.stop() },
        watchTimer: { refresh in
            NotchTimerService.shared.$session.receive(on: DispatchQueue.main)
                .sink { _ in MainActor.assumeIsolated { refresh() } }
        },
        watchCalendar: { refresh in
            NotchCalendarService.shared.$countdown.receive(on: DispatchQueue.main)
                .sink { _ in MainActor.assumeIsolated { refresh() } }
        },
        timerTicker: {
            ClosedIslandTicker(id: TimerIndicator.id, hooks: .init(
                isOn: { PortHost.defaults.bool(forKey: TimerIndicator.switchKey) },
                make: { _ in
                    let service = NotchTimerService.shared
                    return TimerIndicator.indicator(TimerReading(session: service.session, now: service.now))
                },
                post: { AmbientCenter.shared.post($0) },
                withdraw: { AmbientCenter.shared.withdraw(id: $0) }))
        },
        calendarTicker: {
            ClosedIslandTicker(id: CalendarIndicator.id, hooks: .init(
                isOn: { PortHost.defaults.bool(forKey: CalendarIndicator.switchKey) },
                make: { now in
                    guard let countdown = NotchCalendarService.shared.countdown, countdown.isShown(at: now) else { return nil }
                    return CalendarIndicator.indicator(title: countdown.event.title, target: countdown.target,
                                                       ongoing: countdown.ongoing, now: now)
                },
                post: { AmbientCenter.shared.post($0) },
                withdraw: { AmbientCenter.shared.withdraw(id: $0) }))
        })
}

/// The timer lane: four ported features, bound as new registry features, all off until the user turns them on.
///
/// - `notchTimer`: timer, Pomodoro (focus, short and long breaks, auto-next) and stopwatch, with the alarm sound at
///   the end. Memory-only session, as upstream. The end of a session is an alert in the closed island; the running
///   clock shows there only when the user switched it on.
/// - `notchCalendar`: the agenda (EventKit, read-only). The Calendar permission is asked by a click inside the tab
///   (the ported view's own "Autoriser"), never at start. The next appointment shows in the closed island only on request.
/// - `notchAccessories`: Bluetooth connection and low-battery alerts, from the system monitor's peripheral sampler.
/// - `notchNotifications`: mirrors notifications read from Notification Center through Accessibility (the registry's
///   gate waits for the grant and never prompts). Opening a mirrored notification activates its app, as upstream.
enum TimerLane {
    /// Holds the two service subscriptions between a start and its stop.
    private final class WatchBag {
        var timer: AnyCancellable?
        var calendar: AnyCancellable?
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: TimerRuntime) {
        let timerTicker = runtime.timerTicker()
        let calendarTicker = runtime.calendarTicker()
        let watches = WatchBag()

        binding.bind(.notchTimer, start: {
            PortIslandHosting.acquire("timer")
            runtime.syncTimer()
            watches.timer = runtime.watchTimer { timerTicker.refresh() }
            timerTicker.refresh()
        }, stop: {
            watches.timer = nil
            runtime.stopTimer()
            timerTicker.stop()
            PortIslandHosting.release("timer")
        })
        binding.bind(.notchCalendar, start: {
            PortIslandHosting.acquire("calendar")
            runtime.syncCalendar()
            watches.calendar = runtime.watchCalendar { calendarTicker.refresh() }
            calendarTicker.refresh()
        }, stop: {
            watches.calendar = nil
            runtime.stopCalendar()
            calendarTicker.stop()
            PortIslandHosting.release("calendar")
        })
        binding.bind(.notchAccessories, start: {
            PortIslandHosting.acquire("accessories")
            runtime.syncAccessories()
        }, stop: {
            runtime.stopAccessories()
            PortIslandHosting.release("accessories")
        })
        binding.bind(.notchNotifications, start: {
            PortIslandHosting.acquire("notifications")
            runtime.syncNotifications()
        }, stop: {
            runtime.stopNotifications()
            PortIslandHosting.release("notifications")
        })
    }
}

// MARK: - Island tabs

/// The four tabs of the lane. Wiring them into the island's groups is `ShellTabs` / `ShellLayout` (outside this
/// lane); each value is ready to add.
public enum PortIslandTimer {
    @MainActor public static func timerTab() -> IslandTab {
        IslandTab(id: "timer", title: "Minuteur", systemImage: "timer") { AnyView(TimerIslandTab()) }
    }

    @MainActor public static func calendarTab() -> IslandTab {
        IslandTab(id: "calendar", title: "Calendrier", systemImage: "calendar") { AnyView(CalendarIslandTab()) }
    }

    @MainActor public static func notificationsTab() -> IslandTab {
        IslandTab(id: "notifications", title: "Notifications", systemImage: "bell") { AnyView(NotificationsIslandTab()) }
    }

    @MainActor public static func accessoriesTab() -> IslandTab {
        IslandTab(id: "accessories", title: "Accessoires", systemImage: "battery.25percent") {
            AnyView(AccessoriesIslandTab())
        }
    }
}

private extension View {
    /// The ported views draw for the island: dark, island presentation, the host's defaults.
    func hostedPortedView() -> some View {
        environment(\.notchPresentation, true)
            .environment(\.colorScheme, .dark)
            .defaultAppStorage(PortHost.defaults)
    }
}

/// A feature that is off says so, with the way to turn it on: a hidden or empty tab hides what is missing.
private struct FeatureOffNotice: View {
    let feature: AppFeature
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: feature.symbolName).font(.title2).foregroundStyle(.secondary)
            Text("\(title) est désactivé").font(.headline)
            Text("Activez-le dans Fonctionnalités pour l’utiliser ici.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

private struct ClosedIslandSwitch: View {
    let title: String
    let key: String
    @AppStorage private var isOn: Bool

    init(title: String, key: String) {
        self.title = title
        self.key = key
        _isOn = AppStorage(wrappedValue: false, key, store: PortHost.defaults)
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .accessibilityHint("Affiche un repère dans l’île fermée. Désactivé par défaut.")
    }
}

private struct TimerIslandTab: View {
    @State private var on = AppFeature.notchTimer.isAvailable

    var body: some View {
        GeometryReader { proxy in
            if on {
                VStack(spacing: 8) {
                    NotchTimerView(size: proxy.size)
                    ClosedIslandSwitch(title: "Afficher le minuteur dans l’île fermée", key: TimerIndicator.switchKey)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            } else {
                FeatureOffNotice(feature: .notchTimer, title: "Le minuteur")
            }
        }
        .hostedPortedView()
        .onAppear { on = AppFeature.notchTimer.isAvailable }
    }
}

private struct CalendarIslandTab: View {
    @State private var on = AppFeature.notchCalendar.isAvailable

    var body: some View {
        GeometryReader { proxy in
            if on {
                VStack(spacing: 8) {
                    NotchCalendarView(size: proxy.size)
                    ClosedIslandSwitch(title: "Afficher le prochain rendez-vous dans l’île fermée",
                                       key: CalendarIndicator.switchKey)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            } else {
                FeatureOffNotice(feature: .notchCalendar, title: "Le calendrier")
            }
        }
        .hostedPortedView()
        .onAppear { on = AppFeature.notchCalendar.isAvailable }
    }
}

private struct NotificationsIslandTab: View {
    @State private var on = AppFeature.notchNotifications.isAvailable

    var body: some View {
        GeometryReader { proxy in
            if on {
                NotchNotificationsView(size: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            } else {
                FeatureOffNotice(feature: .notchNotifications, title: "Le miroir de notifications")
            }
        }
        .hostedPortedView()
        .onAppear { on = AppFeature.notchNotifications.isAvailable }
    }
}

/// The batteries of the connected accessories, as the system monitor reads them. Native: upstream shows accessories
/// only as notices, and a list is the thing to open the island for.
struct AccessoryRowModel: Equatable, Identifiable {
    let id: String
    let name: String
    let percent: Int
    let symbol: String
    var isLow: Bool { percent < NotchAccessorySupport.lowThreshold }
    var spoken: String { "\(name), \(percent) pour cent\(isLow ? ", batterie faible" : "")" }

    static func rows(from devices: [PeripheralBatteryDevice]) -> [AccessoryRowModel] {
        devices
            .map { AccessoryRowModel(id: $0.id, name: $0.name, percent: min(100, max(0, $0.percent)),
                                     symbol: NotchAccessorySupport.symbol(for: $0.kind, name: $0.name)) }
            .sorted { ($0.percent, $0.name) < ($1.percent, $1.name) }
    }
}

private struct AccessoriesIslandTab: View {
    @State private var on = AppFeature.notchAccessories.isAvailable
    @State private var rows: [AccessoryRowModel] = []

    var body: some View {
        Group {
            if !on {
                FeatureOffNotice(feature: .notchAccessories, title: "Les accessoires")
            } else if rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.title2).foregroundStyle(.secondary)
                    Text("Aucun accessoire avec batterie").font(.headline)
                    Text("Les claviers, souris, trackpads et casques Bluetooth connectés apparaissent ici avec leur niveau.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(rows) { row in
                            HStack(spacing: 10) {
                                Image(systemName: row.symbol).frame(width: 22)
                                Text(row.name).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(row.percent) %").monospacedDigit()
                                    .foregroundStyle(row.isLow ? Color.orange : Color.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(row.spoken)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .hostedPortedView()
        .onAppear { on = AppFeature.notchAccessories.isAvailable }
        .onReceive(SystemMonitor.shared.$snapshot.map(\.peripheralBatterySample.devices).removeDuplicates()
            .receive(on: DispatchQueue.main)) { rows = AccessoryRowModel.rows(from: $0) }
    }
}
