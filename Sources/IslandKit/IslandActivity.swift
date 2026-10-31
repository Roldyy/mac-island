import Foundation
import IslandUI

// FROZEN W0 contract (types only). Lane L3 writes `ActivityCenter`, `ActivityArbiter` and `CompactStrip`
// in their own files; nobody else edits this file.

/// Who wins a wing. Higher rawValue wins: alert > Claude waiting > Claude working > music > ambient.
public enum ActivityPriority: Int, Comparable, Sendable {
    case ambient = 0, music, claudeWorking, claudeWaiting, alert
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One glyph (+ optional short text) shown in a wing of the closed island.
public struct CompactItem: Equatable, Sendable {
    public var symbol: String
    public var text: String?
    public var status: IslandStatus
    /// 0...1 shows a thin ring or bar; nil shows none.
    public var progress: Double?

    public init(symbol: String, text: String? = nil, status: IslandStatus = .neutral, progress: Double? = nil) {
        self.symbol = symbol
        self.text = text
        self.status = status
        self.progress = progress
    }
}

/// What a feature publishes about itself while something is going on.
public struct IslandActivity: Identifiable, Equatable, Sendable {
    public let id: String
    /// Feature id (`FeatureDescriptor.id`) that owns the activity.
    public let source: String
    public var priority: ActivityPriority
    public var leading: CompactItem?
    public var trailing: CompactItem?
    /// An alert that has no room in a wing shows as a dot on the island edge.
    public var showsDot: Bool

    public init(id: String, source: String, priority: ActivityPriority,
                leading: CompactItem? = nil, trailing: CompactItem? = nil, showsDot: Bool = false) {
        self.id = id
        self.source = source
        self.priority = priority
        self.leading = leading
        self.trailing = trailing
        self.showsDot = showsDot
    }
}

/// What the closed island draws. Output of the pure `ActivityArbiter`.
public struct ActivityLayout: Equatable, Sendable {
    public var leading: CompactItem?
    public var trailing: CompactItem?
    public var dot: IslandStatus?

    public static let empty = ActivityLayout(leading: nil, trailing: nil, dot: nil)

    public init(leading: CompactItem?, trailing: CompactItem?, dot: IslandStatus?) {
        self.leading = leading
        self.trailing = trailing
        self.dot = dot
    }

    public var isEmpty: Bool { leading == nil && trailing == nil && dot == nil }
}
