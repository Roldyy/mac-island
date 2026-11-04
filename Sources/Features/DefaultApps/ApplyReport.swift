import Foundation

public enum ItemResult: Equatable, Sendable {
    case success
    /// macOS answered without error but the value read back is not the new one.
    case unverified
    case failure(String)
    /// Not attempted (and why).
    case skipped(String)

    public var isFailure: Bool { if case .failure = self { true } else { false } }
}

public struct ItemOutcome: Identifiable, Equatable, Sendable {
    public let kind: ChangeKind
    public let identifier: String
    public let title: String
    public let result: ItemResult
    public var id: String { "\(kind.rawValue):\(identifier)" }
    public var key: String { id }
}

/// Per-item result of one apply or undo.
public struct ApplyReport: Equatable, Sendable {
    public var outcomes: [ItemOutcome]
    /// The run stopped before the end (a refusal in macOS's sheet, or repeated failures).
    public var stoppedEarly: Bool
    public var notice: String?

    public static let empty = ApplyReport(outcomes: [], stoppedEarly: false, notice: nil)

    public var successCount: Int { outcomes.filter { $0.result == .success }.count }
    public var failureCount: Int { outcomes.filter { $0.result.isFailure }.count }
    public var skippedCount: Int { outcomes.filter { if case .skipped = $0.result { true } else { false } }.count }
}

/// Stops a serial run: at once when the user refuses macOS's sheet, after `limit` failures in a row otherwise.
/// Nothing is ever retried.
struct RunBreaker {
    static let limit = 3
    private(set) var consecutiveFailures = 0
    private(set) var tripped = false

    mutating func record(_ error: Error) {
        consecutiveFailures += 1
        let ls = error as? LaunchServicesError
        // A timeout stops the run too: the pending macOS call or sheet may still be open, never queue another behind it.
        if ls?.userCancelled == true || ls?.timedOut == true || consecutiveFailures >= Self.limit { tripped = true }
    }

    /// Stops the run without counting a failure (the feature was switched off).
    mutating func stop() { tripped = true }

    mutating func recordSuccess() { consecutiveFailures = 0 }
}

/// One thing the undo will put back.
public struct UndoItem: Identifiable, Equatable, Sendable {
    public let kind: ChangeKind
    public let identifier: String
    /// Bundle id to restore, nil when the journal never knew the previous one.
    public let restoreTo: String?
    /// The handler this feature set last: the undo only acts while this is still the live value.
    public let expectedCurrent: String
    public var id: String { "\(kind.rawValue):\(identifier)" }
}

/// Builds the undo of some journal entries (oldest first). Pure.
public enum UndoPlanner {
    /// `originals` (when given) wins over the previous handler of the entries: "Tout restaurer" goes back to what the
    /// type had before this feature ever touched it.
    public static func plan(entries: [JournalEntry], originals: [String: String] = [:]) -> [UndoItem] {
        var order: [String] = []
        var restore: [String: (kind: ChangeKind, id: String, to: String?)] = [:]
        var expected: [String: String] = [:]
        for entry in entries {
            for change in entry.changes where change.state != .failed {
                if restore[change.key] == nil {
                    restore[change.key] = (change.kind, change.identifier, change.previousBundleID)
                    order.append(change.key)
                }
                expected[change.key] = entry.replacementBundleID
            }
        }
        return order.compactMap { key in
            guard let r = restore[key], let e = expected[key] else { return nil }
            return UndoItem(kind: r.kind, identifier: r.id, restoreTo: originals[key] ?? r.to, expectedCurrent: e)
        }
    }
}
