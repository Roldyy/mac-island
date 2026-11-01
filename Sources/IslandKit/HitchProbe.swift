import CoreFoundation
import Darwin
import Foundation
import os

/// A main-thread watchdog: how long does one pass of the main run loop keep the thread busy?
///
/// A `CFRunLoopObserver` on the main run loop marks the start of each pass (the wake-up, which also covers the
/// main dispatch queue, then the timers and sources phases) and its end (`beforeWaiting`, run last so the
/// Core Animation commit counts). Any pass longer than the threshold (8 ms by default: one 120 Hz frame) is a
/// hitch. Each hitch goes to `os_signpost` (Instruments, category `hitch`), to a ring buffer and, with
/// `MIS_HITCH_LOG`, to a file.
///
/// Every pass is timed twice: on the wall clock (what the user sees) and in main-thread CPU time (what the
/// code costs, unaffected by a busy machine preempting the thread). Hitches are counted on the wall clock;
/// the tests budget the CPU time so a loaded CI machine does not make them flaky.
///
/// Zero cost when off: nothing is installed until `start()`. The product starts it only when the environment
/// variable `MIS_HITCH_LOG` is set (`startIfRequested`). Counts and durations only: no content, no names.
///
/// Reading the log: `MIS_HITCH_LOG=1` writes `<NSTemporaryDirectory>/mis-hitch.log`; `MIS_HITCH_LOG=/some/file`
/// writes there. One line per hitch: `<seconds since the probe started> <wall ms> <cpu ms>`; a `# summary ...`
/// line (`HitchStats.line`) is written when the probe stops and by `dumpSummary()`.
public final class HitchProbe: @unchecked Sendable {
    public static let shared = HitchProbe()
    public static let environmentKey = "MIS_HITCH_LOG"
    public static let defaultThresholdMilliseconds = 8.0
    public static let ringCapacity = 256
    /// Bound on the per-iteration samples kept by `captureAll`, so a long run cannot grow without limit.
    public static let captureLimit = 200_000

    public struct Hitch: Equatable, Sendable {
        /// Seconds since the probe started.
        public let at: Double
        public let milliseconds: Double
        /// Main-thread CPU time of the same pass.
        public let cpuMilliseconds: Double
    }

    private struct State {
        var running = false
        var captureAll = false
        var thresholdNanos: UInt64 = 8_000_000
        var epoch: UInt64 = 0
        var ring: [Hitch] = []
        var next = 0
        var totalHitches = 0
        var iterations = 0
        var all: [Double] = []
        var allCPU: [Double] = []
        var logURL: URL?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let signposter = OSSignposter(subsystem: "be.roldy.macisland", category: "hitch")
    private let writer = DispatchQueue(label: "be.roldy.macisland.hitch-log", qos: .utility)

    // Touched only from the main thread (the observer callback), so no lock.
    private var iterationStart: UInt64 = 0
    private var iterationCPUStart: UInt64 = 0
    private var observer: CFRunLoopObserver?

    public init() {}

    public var isRunning: Bool { state.withLock { $0.running } }

    /// Starts the probe when the environment asks for it. Returns whether it is running afterwards.
    @discardableResult
    public func startIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let value = environment[Self.environmentKey], !value.isEmpty, value != "0" else { return isRunning }
        let url = value.hasPrefix("/")
            ? URL(fileURLWithPath: value)
            : URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-hitch.log")
        start(logURL: url)
        return true
    }

    /// Installs the observer on the main run loop (call it on the main thread). `captureAll` also keeps every
    /// pass's durations, for the harness and its percentiles; the product leaves it off.
    public func start(thresholdMilliseconds: Double = HitchProbe.defaultThresholdMilliseconds,
                      captureAll: Bool = false, logURL: URL? = nil) {
        let already = state.withLock { s -> Bool in
            if s.running { return true }
            s = State()
            s.running = true
            s.captureAll = captureAll
            s.thresholdNanos = UInt64(max(thresholdMilliseconds, 0) * 1_000_000)
            s.epoch = Self.now()
            s.ring.reserveCapacity(Self.ringCapacity)
            s.logURL = logURL
            return false
        }
        guard !already else { return }
        if let logURL { writer.async { try? Data().write(to: logURL) } }
        let activities: CFRunLoopActivity = [.beforeTimers, .beforeSources, .afterWaiting, .beforeWaiting]
        // Order above Core Animation's commit observer (2_000_000): its work belongs to the pass.
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 3_000_000) {
            [unowned self] _, activity in
            self.handle(activity)
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    public func stop() {
        guard state.withLock({ s -> Bool in
            let was = s.running
            s.running = false
            return was
        }) else { return }
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            CFRunLoopObserverInvalidate(observer)
        }
        observer = nil
        iterationStart = 0
        dumpSummary()
    }

    // MARK: - Reading

    /// The most recent hitches, oldest first (at most `ringCapacity`).
    public var hitches: [Hitch] {
        state.withLock { s in
            guard s.ring.count == Self.ringCapacity else { return s.ring }
            return Array(s.ring[s.next...] + s.ring[..<s.next])
        }
    }

    /// Hitches seen since `start`, including those the ring has already dropped.
    public var totalHitches: Int { state.withLock { $0.totalHitches } }

    /// Every pass (wall milliseconds) since `start` when `captureAll` was set, otherwise empty.
    public var capturedMilliseconds: [Double] { state.withLock { $0.all } }

    /// Main-thread CPU milliseconds of every pass since `start`, same order, when `captureAll` was set.
    public var capturedCPUMilliseconds: [Double] { state.withLock { $0.allCPU } }

    /// With `captureAll`: stats over every pass. Without it: counts over the hitches the ring still holds.
    public func stats() -> HitchStats {
        let (all, ring, threshold, iterations, total) = state.withLock {
            ($0.all, $0.ring, Double($0.thresholdNanos) / 1e6, $0.iterations, $0.totalHitches)
        }
        if !all.isEmpty { return HitchStats(milliseconds: all, threshold: threshold) }
        var stats = HitchStats(milliseconds: ring.map(\.milliseconds), threshold: threshold)
        stats.iterations = iterations
        stats.overThreshold = total
        return stats
    }

    /// Same as `stats()` over main-thread CPU time (needs `captureAll`; empty stats otherwise).
    public func cpuStats() -> HitchStats {
        let (all, threshold) = state.withLock { ($0.allCPU, Double($0.thresholdNanos) / 1e6) }
        return HitchStats(milliseconds: all, threshold: threshold)
    }

    /// Forgets what was recorded, keeps the probe running (the harness calls this between interactions).
    public func reset() {
        state.withLock { s in
            s.ring.removeAll(keepingCapacity: true)
            s.next = 0
            s.totalHitches = 0
            s.iterations = 0
            s.all.removeAll(keepingCapacity: true)
            s.allCPU.removeAll(keepingCapacity: true)
        }
    }

    /// Appends the `# summary` line to the log file, when there is one.
    public func dumpSummary() {
        guard let url = state.withLock({ $0.logURL }) else { return }
        let line = "# summary \(stats().line)\n"
        writer.async { Self.append(line, to: url) }
    }

    // MARK: - Observer (main thread)

    private func handle(_ activity: CFRunLoopActivity) {
        switch activity {
        case .afterWaiting:
            beginPass()  // the thread just woke: sleeping time is not work
        case .beforeTimers, .beforeSources:
            if iterationStart == 0 { beginPass() }
        case .beforeWaiting:
            guard iterationStart != 0 else { return }
            let end = Self.now()
            let elapsed = end &- iterationStart
            let cpu = Self.cpuNow() &- iterationCPUStart
            iterationStart = 0
            record(elapsedNanos: elapsed, cpuNanos: cpu, end: end)
        default:
            break
        }
    }

    private func beginPass() {
        iterationStart = Self.now()
        iterationCPUStart = Self.cpuNow()
    }

    /// Visible to tests: one finished pass.
    func record(elapsedNanos: UInt64, cpuNanos: UInt64 = 0, end: UInt64 = HitchProbe.now()) {
        let milliseconds = Double(elapsedNanos) / 1e6
        let cpuMilliseconds = Double(cpuNanos) / 1e6
        let hitch: Hitch? = state.withLock { s in
            guard s.running else { return nil }
            s.iterations += 1
            if s.captureAll, s.all.count < Self.captureLimit {
                s.all.append(milliseconds)
                s.allCPU.append(cpuMilliseconds)
            }
            guard elapsedNanos > s.thresholdNanos else { return nil }
            let hitch = Hitch(at: Double(end &- s.epoch) / 1e9, milliseconds: milliseconds, cpuMilliseconds: cpuMilliseconds)
            if s.ring.count < Self.ringCapacity {
                s.ring.append(hitch)
            } else {
                s.ring[s.next] = hitch
                s.next = (s.next + 1) % Self.ringCapacity
            }
            s.totalHitches += 1
            return hitch
        }
        guard let hitch else { return }
        signposter.emitEvent("hitch", "\(hitch.milliseconds, format: .fixed(precision: 1)) ms")
        if let url = state.withLock({ $0.logURL }) {
            let line = String(format: "%.3f %.1f %.1f\n", hitch.at, hitch.milliseconds, hitch.cpuMilliseconds)
            writer.async { Self.append(line, to: url) }
        }
    }

    static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    static func cpuNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }

    private static func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
