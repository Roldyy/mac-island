import Foundation

/// The two-click rule of a confirming action, with no timer and no view: the row keeps `armed` in its state and
/// clears it after `window`; every decision is a pure function of (action, armed, now).
public enum StatusChipConfirmation {
    /// Seconds the "Confirmer" button stays armed.
    public static let window: TimeInterval = 3

    public struct Armed: Equatable, Sendable {
        public var actionID: String
        /// What the first click was shown for. A refreshed reading can reuse the id for another target
        /// ("Quitter Safari" then "Quitter Xcode"): the confirmation then no longer counts.
        public var title: String
        public var at: Date
        public init(actionID: String, title: String = "", at: Date) {
            self.actionID = actionID
            self.title = title
            self.at = at
        }
    }

    public enum Decision: Equatable, Sendable {
        /// Run the handler now.
        case perform
        /// First click: show "Confirmer" and start the countdown.
        case arm
    }

    /// Whether `armed` still counts at `now` (also false for a clock that went backwards).
    public static func isArmed(_ armed: Armed?, for actionID: String, title: String = "", now: Date) -> Bool {
        guard let armed, armed.actionID == actionID, armed.title == title else { return false }
        let elapsed = now.timeIntervalSince(armed.at)
        return elapsed >= 0 && elapsed < window
    }

    public static func decide(_ action: StatusChipAction, armed: Armed?, now: Date) -> Decision {
        guard action.needsConfirmation else { return .perform }
        return isArmed(armed, for: action.id, title: action.title, now: now) ? .perform : .arm
    }
}
