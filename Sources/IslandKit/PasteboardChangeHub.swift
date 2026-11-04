import AppKit
import Foundation

/// ONE watcher of `NSPasteboard.general.changeCount` for every clipboard service (history, URL cleaner, auto clear).
/// Before, each of them kept its own repeating timer and read the count itself, three or four wakeups per second
/// for the same number. Now a single timer ticks, the count is read ONCE per tick (off the main thread: a read can
/// block behind an app that promised pasteboard content, and a blocked main thread freezes the event taps), and every
/// subscriber receives that count.
///
/// The timer exists only while at least one subscriber is registered and runs at the fastest interval asked for;
/// the last subscriber leaving cancels it. A subscriber may be called more often than its own interval and must
/// compare the count with the one it last acted on (all of them already did). A count can arrive slightly late
/// (read before a write the subscriber itself just made): treat a lower count as stale, never as a copy.
@MainActor
public final class PasteboardChangeHub {
    public static let shared = PasteboardChangeHub()

    /// Reads the change count and answers on the main actor, possibly later.
    public typealias Reader = @MainActor (_ done: @escaping @MainActor (Int) -> Void) -> Void
    /// Repeating tick; returns the closure that cancels it.
    public typealias Scheduler = @MainActor (_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> () -> Void
    public typealias Token = UUID

    private struct Subscriber {
        var interval: TimeInterval
        var handler: @MainActor (Int) -> Void
    }

    private var subscribers: [Token: Subscriber] = [:]
    private let reader: Reader
    private let schedule: Scheduler
    private var cancelTimer: (() -> Void)?
    private var tickInterval: TimeInterval?
    private var readInFlight = false
    private var readGeneration = 0

    /// How many reads of the pasteboard the hub has started (a test asserts "one per tick").
    public private(set) var readCount = 0

    public init(reader: @escaping Reader = PasteboardChangeHub.generalReader,
                schedule: @escaping Scheduler = PasteboardChangeHub.liveScheduler) {
        self.reader = reader
        self.schedule = schedule
    }

    /// True while the timer runs (that is, while someone is subscribed).
    public var isRunning: Bool { cancelTimer != nil }
    public var subscriberCount: Int { subscribers.count }

    /// Registers `handler`, called with the change count on the main actor roughly every `interval` seconds.
    @discardableResult
    public func subscribe(interval: TimeInterval, _ handler: @escaping @MainActor (_ changeCount: Int) -> Void) -> Token {
        let token = Token()
        subscribers[token] = Subscriber(interval: interval, handler: handler)
        reschedule()
        return token
    }

    public func unsubscribe(_ token: Token) {
        guard subscribers.removeValue(forKey: token) != nil else { return }
        reschedule()
    }

    /// One tick: one read, then every subscriber gets the count. A read still in flight (a wedged pasteboard server)
    /// skips the tick instead of piling up reads; it is abandoned after 5 s.
    public func tick() {
        guard !subscribers.isEmpty, !readInFlight else { return }
        readInFlight = true
        readGeneration &+= 1
        readCount += 1
        let generation = readGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.readGeneration == generation, self.readInFlight else { return }
                self.readInFlight = false
            }
        }
        reader { [weak self] count in
            guard let self, self.readGeneration == generation else { return }
            self.readInFlight = false
            for subscriber in Array(self.subscribers.values) { subscriber.handler(count) }
        }
    }

    private func reschedule() {
        let wanted = subscribers.values.map(\.interval).min()
        guard wanted != tickInterval else { return }
        cancelTimer?()
        cancelTimer = nil
        tickInterval = wanted
        readGeneration &+= 1   // a read answering for the old timer is dropped
        readInFlight = false
        guard let wanted else { return }
        cancelTimer = schedule(wanted) { [weak self] in self?.tick() }
    }

    // MARK: - Live

    private static let readQueue = DispatchQueue(label: "mac-island.pasteboard.changecount", qos: .utility)

    /// The general pasteboard, read on a private serial queue.
    public static let generalReader: Reader = { done in
        readQueue.async {
            let count = NSPasteboard.general.changeCount
            DispatchQueue.main.async { MainActor.assumeIsolated { done(count) } }
        }
    }

    /// A repeating main run loop timer with a tolerance, so the system can coalesce its wakeups with others.
    public static let liveScheduler: Scheduler = { interval, tick in
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        timer.tolerance = min(0.25, interval * 0.3)
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
