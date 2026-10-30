import Foundation

/// Show/hide timing of the preview: delay on the icon, grace when leaving, panel counts as "still here".
/// Pure: the caller passes the time from its injected clock.
struct PreviewStateMachine: Equatable {
    enum Phase: Equatable {
        case idle
        case pending(id: String, since: TimeInterval)
        case showing(id: String)
        case leaving(id: String, since: TimeInterval)
    }
    enum Command: Equatable { case none, show(String), hide }

    var delay: TimeInterval
    var grace: TimeInterval
    private(set) var phase: Phase = .idle

    init(delay: TimeInterval, grace: TimeInterval) {
        self.delay = delay
        self.grace = grace
    }

    var isIdle: Bool { phase == .idle }

    mutating func update(hoveredIcon: String?, overPanel: Bool, now: TimeInterval) -> Command {
        switch phase {
        case .idle:
            guard let id = hoveredIcon else { return .none }
            phase = .pending(id: id, since: now)
            return update(hoveredIcon: hoveredIcon, overPanel: overPanel, now: now)
        case let .pending(id, since):
            guard hoveredIcon == id else {
                phase = hoveredIcon.map { .pending(id: $0, since: now) } ?? .idle
                return .none
            }
            guard now - since >= delay - 1e-9 else { return .none }
            phase = .showing(id: id)
            return .show(id)
        case let .showing(id):
            if overPanel || hoveredIcon == id { return .none }
            if let other = hoveredIcon {
                phase = .showing(id: other)
                return .show(other)
            }
            phase = .leaving(id: id, since: now)
            return .none
        case let .leaving(id, since):
            if overPanel || hoveredIcon == id {
                phase = .showing(id: id)
                return .none
            }
            if let other = hoveredIcon {
                phase = .showing(id: other)
                return .show(other)
            }
            guard now - since >= grace - 1e-9 else { return .none }
            phase = .idle
            return .hide
        }
    }

    /// Feature turned off or stopped.
    mutating func cancel() -> Command {
        defer { phase = .idle }
        switch phase {
        case .showing, .leaving: return .hide
        case .idle, .pending: return .none
        }
    }
}
