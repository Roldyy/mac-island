import Combine
import Foundation
import IslandUI

/// Gathers every indicator of the closed island, applies the user's settings and the rotation, and publishes
/// what each wing shows. Sources that are not activities (battery, keep awake) post here; the activity
/// engine's winners (Claude, limits, music, alerts) come in through `AmbientBridge`.
///
/// Event driven: the only timers are the rotation step (only while something rotates and the strip is on
/// screen) and one wake-up when a Claude clock needs another digit group.
@MainActor
public final class AmbientCenter: ObservableObject {
    public static let shared = AmbientCenter()

    @Published public private(set) var content = ClosedIslandContent.empty

    /// Feeds `IslandController(activityCenter:)`: it measures this center's layout to size the panel, so the
    /// panel is as wide as the strip needs, no wider. Never drawn.
    public let widthProxy: ActivityCenter

    /// A hardware notch splits the content into two wings; without one the groups sit together in the pill.
    public var isNotched: Bool {
        didSet { if isNotched != oldValue { recompute() } }
    }

    public private(set) var settings: ClosedIslandSettings
    public let rotationInterval: Duration

    private var posted: [String: AmbientIndicator] = [:]
    private var bridged: [AmbientIndicator] = []
    private var layout = ActivityLayout.empty
    private var claude: ClaudeWorkSample?
    private var step = 0
    private var visible = true
    private var rotation: Task<Void, Never>?
    private var clockWake: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    /// `sleep` and `now` are injectable so a test drives rotation and the clock without real time.
    public init(activity: ActivityCenter? = nil, preferences: ClosedIslandPreferences? = nil,
                isNotched: Bool = false, rotationInterval: Duration = .seconds(4),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        let preferences = preferences ?? .shared
        self.settings = preferences.settings
        self.isNotched = isNotched
        self.rotationInterval = rotationInterval
        self.sleep = sleep
        self.now = now
        self.widthProxy = ActivityCenter()
        (activity ?? .shared).$layout.sink { [weak self] layout in
            MainActor.assumeIsolated { self?.activityChanged(layout) }
        }.store(in: &subscriptions)
        preferences.$settings.dropFirst().sink { [weak self] settings in
            MainActor.assumeIsolated {
                self?.settings = settings
                self?.recompute()
            }
        }.store(in: &subscriptions)
    }

    // MARK: - Sources

    /// Posting an id again replaces the indicator.
    public func post(_ indicator: AmbientIndicator) {
        guard posted[indicator.id] != indicator else { return }
        posted[indicator.id] = indicator
        recompute()
    }

    public func withdraw(id: String) {
        guard posted.removeValue(forKey: id) != nil else { return }
        recompute()
    }

    /// The Claude session whose clock the wing shows (same winner as the arbiter).
    public func setClaude(_ sample: ClaudeWorkSample?) {
        guard sample != claude else { return }
        claude = sample
        bridged = AmbientBridge.indicators(from: layout, claude: claude)
        recompute()
    }

    /// The closed strip is on screen (island closed). Rotation pauses while it is not.
    public func setVisible(_ on: Bool) {
        guard on != visible else { return }
        visible = on
        scheduleRotation()
    }

    private func activityChanged(_ new: ActivityLayout) {
        layout = new
        bridged = AmbientBridge.indicators(from: new, claude: claude)
        recompute()
    }

    // MARK: - Resolve

    private func recompute() {
        let date = now()
        var resolved = ClosedIslandLayout.resolve(Array(posted.values) + bridged, settings: settings, step: step)
        step = resolved.step
        if isNotched {
            // Each wing is baseWing + extent wide; what does not fit loses its text, then its last element.
            let extent = AmbientMetrics.notchedExtent(resolved, now: date)
            let width = NotchGeometry.baseWing + extent
            resolved.leading = AmbientMetrics.fitted(resolved.leading, width: width, now: date)
            resolved.trailing = AmbientMetrics.fitted(resolved.trailing, width: width, now: date)
        }
        resolved.dot = layout.dot
        if resolved != content { content = resolved }
        publishWidth(AmbientMetrics.extent(resolved, notched: isNotched, now: date))
        scheduleRotation()
        scheduleClockWake(date)
    }

    private func publishWidth(_ extent: CGFloat) {
        if let item = AmbientMetrics.measuringItem(forExtent: extent) {
            widthProxy.post(IslandActivity(id: "ambient.width", source: "ambient", priority: .ambient, leading: item))
        } else {
            widthProxy.withdraw(id: "ambient.width")
        }
    }

    // MARK: - Timers

    private func scheduleRotation() {
        guard visible, content.isRotating else {
            rotation?.cancel()
            rotation = nil
            return
        }
        guard rotation == nil else { return }
        let sleep = self.sleep, interval = rotationInterval
        rotation = Task { [weak self] in
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    func advance() {
        guard content.isRotating else { return }
        step = content.nextStep
        recompute()
    }

    private func scheduleClockWake(_ date: Date) {
        clockWake?.cancel()
        clockWake = nil
        guard let since = content.all.compactMap(\.clockSince).first,
              let seconds = AmbientMetrics.secondsUntilClockWidens(since: since, now: date) else { return }
        let sleep = self.sleep
        clockWake = Task { [weak self] in
            do { try await sleep(.seconds(seconds + 0.2)) } catch { return }
            self?.recompute()
        }
    }
}
