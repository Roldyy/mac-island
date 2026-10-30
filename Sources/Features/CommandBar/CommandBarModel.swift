import AppKit
import Observation

/// What Enter and Cmd+Enter do. Injected so tests never touch NSWorkspace or the pasteboard.
struct BarActions {
    var open: (URL) -> Void
    var reveal: (URL) -> Void
    var copy: (String) -> Void
    var runCommand: (String) -> Void

    @MainActor static let live = BarActions(
        open: { NSWorkspace.shared.open($0) },
        reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        copy: { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        },
        runCommand: { _ in })
}

/// State of the palette: the query, the ranked rows and the selection. The query text lives here
/// only while the panel is open; it is not logged and not stored (habits keep result ids only).
@MainActor
@Observable
final class CommandBarModel {
    static let rowLimit = 8

    var query = ""
    private(set) var results: [BarResult] = []
    var selectedIndex = 0

    @ObservationIgnored private let sources: [any ResultSource]
    @ObservationIgnored private let habits: HabitStore
    @ObservationIgnored private let settings: () -> CommandBarSettings
    @ObservationIgnored private let actions: BarActions

    init(sources: [any ResultSource], habits: HabitStore,
         settings: @escaping () -> CommandBarSettings = { CommandBarSettings() },
         actions: BarActions? = nil) {
        self.sources = sources
        self.habits = habits
        self.settings = settings
        self.actions = actions ?? .live
    }

    func reset() {
        query = ""
        results = []
        selectedIndex = 0
    }

    /// Fast sources first, then the slow ones merged in. A superseded run (cancelled, or the query
    /// moved on) leaves the screen alone.
    func refresh() async {
        let asked = query
        let current = settings()
        let enabled = sources.filter { current.sourceEnabled($0.sourceID) }
        var pool = await gather(enabled.filter { !$0.isSlow }, asked)
        guard !Task.isCancelled, asked == query else { return }
        apply(pool, asked)

        let slow = enabled.filter(\.isSlow)
        guard !slow.isEmpty, !asked.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        pool += await gather(slow, asked)
        guard !Task.isCancelled, asked == query else { return }
        apply(pool, asked)
    }

    private func gather(_ list: [any ResultSource], _ q: String) async -> [BarResult] {
        await withTaskGroup(of: [BarResult].self) { group in
            for s in list { group.addTask { await s.results(for: q) } }
            var all: [BarResult] = []
            for await part in group { all += part }
            return all
        }
    }

    private func apply(_ pool: [BarResult], _ q: String) {
        let weights = settings().habitsEnabled ? habits.weights(now: Date()) : .none
        let previous = results.indices.contains(selectedIndex) ? results[selectedIndex].id : nil
        results = ResultRanker.rank(pool, query: q, habits: weights, now: Date(), limit: Self.rowLimit)
        selectedIndex = previous.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(results.count - 1, max(0, selectedIndex + delta))
    }

    /// Enter runs the selected row; with `reveal`, Cmd+Enter shows it in Finder instead.
    /// Returns false when there was nothing to do (no row, or nothing to reveal).
    @discardableResult
    func activate(reveal: Bool) -> Bool {
        guard results.indices.contains(selectedIndex) else { return false }
        let r = results[selectedIndex]
        if reveal {
            guard let url = r.reveal else { return false }
            actions.reveal(url)
        } else {
            switch r.action {
            case .open(let url): actions.open(url)
            case .copy(let text): actions.copy(text)
            case .runCommand(let id): actions.runCommand(id)
            }
        }
        if r.tracksHabit, settings().habitsEnabled { habits.record(r.id) }
        return true
    }
}
