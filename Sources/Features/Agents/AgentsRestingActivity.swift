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

extension AgentsRestingActivity {
    /// What the closed island shows for Claude at rest, whatever the "show the limit" setting says (the
    /// Limites channel switch decides). The week comes from the plan reading; the session only when its row
    /// holds a percentage (a reading older than the 5 h window leaves it nil, so it is never shown as live).
    /// A pending or missing reading gives a reading without numbers: the island then draws nothing for it.
    static func reading(limits: LimitsState, sample: PlanLimitSample?, display: AgentsLimitDisplay,
                        now: Date) -> ClaudeRestReading {
        func used(_ kind: LimitRow.Kind) -> Double? {
            limits.rows.first { $0.kind == kind }?.usedPercent.map { Double($0) / 100 }
        }
        return ClaudeRestReading.make(
            weekUsed: used(.weekly), sessionUsed: used(.session), showLeft: display == .remaining,
            age: sample.map { now.timeIntervalSince($0.date) })
    }
}

@MainActor
protocol AgentsAmbientPosting {
    func setClaudeRest(_ reading: ClaudeRestReading?)
}

extension AmbientCenter: AgentsAmbientPosting {}

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
    private let ambient: (any AgentsAmbientPosting)?
    private let interval: Duration
    private let clock: @Sendable () -> Date
    private var loop: Task<Void, Never>?

    /// `ambient` is the closed island's center (the shared one when nil), which draws Claude at rest; a test may
    /// pass a recorder.
    init(settings: AgentsSettings, limitSource: PlanLimitSource = PlanLimitSource(),
         poster: any AgentsActivityPosting, ambient: (any AgentsAmbientPosting)? = nil,
         interval: Duration = .seconds(60), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.limitSource = limitSource
        self.poster = poster
        self.ambient = ambient ?? AmbientCenter.shared
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
        ambient?.setClaudeRest(nil)
    }

    func refresh() async {
        let source = limitSource
        let sample = await Task.detached(priority: .utility) { source.load() }.value
        guard !Task.isCancelled else { return }
        let now = clock()
        let limits = LimitsState.resolve(sample: sample, block: nil, blockKnown: false, weekTokens: 0, now: now)
        // The closed island's Claude indicator does not depend on the legacy "show the limit" setting.
        ambient?.setClaudeRest(AgentsRestingActivity.reading(limits: limits, sample: sample, display: settings.limitDisplay, now: now))
        guard settings.showsLimitWhenClosed else {
            poster.withdraw(id: AgentsRestingActivity.id)
            return
        }
        if let activity = AgentsRestingActivity.activity(limits: limits, focus: settings.limitFocus, display: settings.limitDisplay) {
            poster.post(activity)
        } else {
            poster.withdraw(id: AgentsRestingActivity.id)
        }
    }
}
