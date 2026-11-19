import AppKit
import Foundation
import IslandKit
import Network

/// Debounces the network path and announces only a change of a stable state. Pure: time comes in as an argument.
///
/// `observe` records the raw state; `settle` (called once the debounce has had time to pass) promotes it to the
/// stable state when it has held for `debounce` seconds. The very first stable state is the baseline: no notice, so
/// launching the app never announces anything. A flap shorter than the debounce never becomes stable.
struct NetworkTransitionFilter: Sendable {
    enum Notice: Equatable, Sendable { case lost, restored }

    let debounce: TimeInterval
    private(set) var stable: Bool?
    private var pending: (online: Bool, since: Date)?

    init(debounce: TimeInterval = 1) { self.debounce = debounce }

    mutating func observe(online: Bool, at now: Date) {
        if online == stable {
            pending = nil
        } else if pending?.online != online {
            pending = (online, now)
        }
    }

    mutating func settle(at now: Date) -> Notice? {
        guard let pending, now.timeIntervalSince(pending.since) >= debounce else { return nil }
        self.pending = nil
        let previous = stable
        stable = pending.online
        guard previous != nil else { return nil }
        return pending.online ? .restored : .lost
    }
}

/// What the island shows for a notice: one alert slot, so the second notice replaces the first.
enum NetworkNotice {
    static let activityID = "networkNotice"
    static let lifetime: Duration = .seconds(3)

    static func activity(for notice: NetworkTransitionFilter.Notice) -> IslandActivity {
        switch notice {
        case .lost:
            IslandActivity(id: activityID, source: IslandExtrasFeature.networkNoticeID, priority: .alert,
                           leading: CompactItem(symbol: "wifi.slash", text: "Réseau perdu", status: .warning))
        case .restored:
            IslandActivity(id: activityID, source: IslandExtrasFeature.networkNoticeID, priority: .alert,
                           leading: CompactItem(symbol: "wifi", text: "Réseau rétabli", status: .success))
        }
    }
}

/// Watches the system network path (Network.framework, no permission) while the feature is on.
@MainActor
final class NetworkNoticeMonitor {
    private var monitor: NWPathMonitor?
    private var filter = NetworkTransitionFilter()
    private let post: @MainActor (IslandActivity) -> Void
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date
    private var settleTask: Task<Void, Never>?
    private var quietUntil: Date?
    private var wakeObserver: NSObjectProtocol?

    /// After the Mac wakes the path often drops and comes back by itself: no notice for this long. The state is still tracked.
    nonisolated static let wakeQuiet: TimeInterval = 10

    init(now: @escaping @Sendable () -> Date = { Date() },
         post: @escaping @MainActor (IslandActivity) -> Void = { ActivityCenter.shared.post($0, expiresAfter: NetworkNotice.lifetime) },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.now = now
        self.post = post
        self.sleep = sleep
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        filter = NetworkTransitionFilter()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.received(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "be.roldy.macisland.network-notice", qos: .utility))
        self.monitor = monitor
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.wokeUp() }
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        settleTask?.cancel()
        settleTask = nil
        quietUntil = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// The Mac just woke up: swallow the notices of the next `wakeQuiet` seconds.
    func wokeUp() {
        quietUntil = now().addingTimeInterval(Self.wakeQuiet)
    }

    func received(online: Bool) {
        guard monitor != nil else { return }
        filter.observe(online: online, at: now())
        settleTask?.cancel()
        let wait = Duration.seconds(filter.debounce) + .milliseconds(50)
        settleTask = Task { [weak self, sleep] in
            do { try await sleep(wait) } catch { return }
            self?.settle()
        }
    }

    private func settle() {
        guard let notice = filter.settle(at: now()) else { return }
        if let quietUntil, now() < quietUntil { return }  // the state moved on, the notice is not worth showing
        post(NetworkNotice.activity(for: notice))
    }
}
