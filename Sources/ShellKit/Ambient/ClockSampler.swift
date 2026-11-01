import Foundation
import IslandKit

/// The clock indicator. One sleep, aligned to the minute boundary: it wakes when the text changes and never
/// between. Nothing runs while the pill is hidden or the clock is off (the hub stops it).
@MainActor
public final class ClockSampler: AmbientSampler {
    public let channel = AmbientChannel.clock

    private let center: AmbientCenter
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let locale: @Sendable () -> Locale
    private var hours: ClockHours = .system
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    public init(center: AmbientCenter, now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                locale: @escaping @Sendable () -> Locale = { Locale.autoupdatingCurrent }) {
        self.center = center
        self.now = now
        self.sleep = sleep
        self.locale = locale
    }

    public var isRunning: Bool { task != nil }

    public func start(settings: ClosedIslandSettings) {
        guard task == nil else { return }
        hours = settings.clockHours
        post()
        // The system can change the text without the minute turning: locale (24 h switch), time zone, clock set.
        let names: [Notification.Name] = [
            NSLocale.currentLocaleDidChangeNotification, NSNotification.Name.NSSystemClockDidChange,
            NSNotification.Name.NSSystemTimeZoneDidChange,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.post()
                    self?.reschedule()
                }
            }
        }
        reschedule()
    }

    public func stop() {
        task?.cancel()
        task = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    public func settingsChanged(_ settings: ClosedIslandSettings) {
        guard settings.clockHours != hours else { return }
        hours = settings.clockHours
        if task != nil { post() }
    }

    private func post() {
        center.post(AmbientReadings.clock(now(), locale: locale(), hours: hours))
    }

    private func reschedule() {
        task?.cancel()
        let sleep = self.sleep, now = self.now
        task = Task { [weak self] in
            while !Task.isCancelled {
                // A hair past the boundary, so the formatter reads the new minute.
                let wait = AmbientFormat.secondsToNextMinute(from: now()) + 0.05
                do { try await sleep(.seconds(wait)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.post()
            }
        }
    }
}
