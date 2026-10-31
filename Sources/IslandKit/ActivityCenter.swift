import Foundation
import IslandUI

/// Features post what they are doing; the center keeps the live set and publishes the arbiter's layout.
@MainActor
public final class ActivityCenter: ObservableObject {
    public static let shared = ActivityCenter()

    @Published public private(set) var layout = ActivityLayout.empty

    private var activities: [String: IslandActivity] = [:]
    private var expiries: [String: Task<Void, Never>] = [:]
    private let sleep: @Sendable (Duration) async throws -> Void

    /// `sleep` is injectable so tests can drive expiry without real time.
    public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Posting an id again replaces the activity and restarts its expiry.
    public func post(_ activity: IslandActivity, expiresAfter: Duration? = nil) {
        expiries.removeValue(forKey: activity.id)?.cancel()
        activities[activity.id] = activity
        if let expiresAfter {
            let id = activity.id
            let sleep = self.sleep
            expiries[id] = Task { [weak self] in
                do { try await sleep(expiresAfter) } catch { return }
                self?.withdraw(id: id)
            }
        }
        publish()
    }

    public func withdraw(id: String) {
        expiries.removeValue(forKey: id)?.cancel()
        guard activities.removeValue(forKey: id) != nil else { return }
        publish()
    }

    /// A feature turning off drops everything it posted.
    public func withdrawAll(source: String) {
        let ids = activities.values.filter { $0.source == source }.map(\.id)
        for id in ids {
            expiries.removeValue(forKey: id)?.cancel()
            activities.removeValue(forKey: id)
        }
        if !ids.isEmpty { publish() }
    }

    private func publish() {
        let next = ActivityArbiter.resolve(Array(activities.values))
        if next != layout { layout = next }
    }
}
