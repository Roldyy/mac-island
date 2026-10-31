import Foundation
import IslandKit
import IslandUI

/// What the closed island shows for the plan limits. Pure.
enum AgentsRestingActivity {
    static let id = "agents.resting"
    static let source = "agents"

    /// nil when the focused limit has no percentage: nothing is shown rather than a guess.
    static func activity(limits: LimitsState, focus: AgentsLimitFocus, display: AgentsLimitDisplay) -> IslandActivity? {
        guard let row = limits.focused(focus), let used = row.usedPercent, let fill = row.fill(display) else { return nil }
        let status: IslandStatus = used >= 90 ? .danger : used >= 75 ? .warning : .neutral
        return IslandActivity(
            id: id, source: source, priority: .ambient,
            leading: CompactItem(symbol: "gauge", text: UsageFormat.percent(fill), status: status, progress: fill))
    }
}

@MainActor
protocol AgentsActivityPosting {
    func post(_ activity: IslandActivity)
    func withdraw(id: String)
}

extension ActivityCenter: AgentsActivityPosting {
    func post(_ activity: IslandActivity) { post(activity, expiresAfter: nil) }
}

/// Keeps the ambient limit activity current while the app runs: reads only the small limits file, never
/// the logs, so a minute-by-minute refresh stays cheap.
@MainActor
final class AgentsRestingController {
    private let settings: AgentsSettings
    private let limitSource: PlanLimitSource
    private let poster: any AgentsActivityPosting
    private let interval: Duration
    private let clock: @Sendable () -> Date
    private var loop: Task<Void, Never>?

    init(settings: AgentsSettings, limitSource: PlanLimitSource = PlanLimitSource(),
         poster: any AgentsActivityPosting, interval: Duration = .seconds(60),
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.limitSource = limitSource
        self.poster = poster
        self.interval = interval
        self.clock = clock
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        poster.withdraw(id: AgentsRestingActivity.id)
    }

    func refresh() async {
        guard settings.showsLimitWhenClosed else {
            poster.withdraw(id: AgentsRestingActivity.id)
            return
        }
        let source = limitSource
        let sample = await Task.detached(priority: .utility) { source.load() }.value
        guard !Task.isCancelled else { return }
        let limits = LimitsState.resolve(sample: sample, block: nil, weekTokens: 0, now: clock())
        if let activity = AgentsRestingActivity.activity(limits: limits, focus: settings.limitFocus, display: settings.limitDisplay) {
            poster.post(activity)
        } else {
            poster.withdraw(id: AgentsRestingActivity.id)
        }
    }
}
