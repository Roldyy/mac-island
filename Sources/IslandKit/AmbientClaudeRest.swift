import Foundation
import IslandUI

/// What the plan reading says at rest, reduced to what the closed island may draw. Pure.
///
/// The week moves slowly, so its ring stays on screen from an old reading, dimmed after `dimAfter` and dropped
/// after `dropWeekAfter` (that window is over). A session percentage is never kept from an old reading: the
/// caller passes it only when it belongs to the open 5 h window.
public struct ClaudeRestReading: Equatable, Sendable {
    public static let dimAfter: TimeInterval = 6 * 3600
    public static let dropWeekAfter: TimeInterval = 7 * 24 * 3600

    /// 0...1 shown on the ring (the week), nil when unknown.
    public var weekFill: Double?
    /// Text of the session percentage, nil when there is no current one.
    public var sessionText: String?
    public var isDimmed: Bool
    public var status: IslandStatus
    /// Spoken by VoiceOver.
    public var label: String

    public var hasNumbers: Bool { weekFill != nil || sessionText != nil }

    /// - Parameters:
    ///   - weekUsed / sessionUsed: share used, 0...1, nil when unknown (pending, no file, outdated).
    ///   - showLeft: the user reads "what is left" rather than "what is used".
    ///   - age: seconds since the plan reading was taken; nil without a reading.
    public static func make(weekUsed: Double?, sessionUsed: Double?, showLeft: Bool, age: TimeInterval?) -> ClaudeRestReading {
        let fresh = age.map { $0 >= 0 && $0 < dropWeekAfter } ?? false
        let week = fresh ? weekUsed.map { min(max($0, 0), 1) } : nil
        let session = age != nil ? sessionUsed.map { min(max($0, 0), 1) } : nil
        func shown(_ used: Double) -> Double { showLeft ? 1 - used : used }
        let worst = max(week ?? 0, session ?? 0)
        var words: [String] = []
        if let week { words.append("semaine \(Int((shown(week) * 100).rounded())) %") }
        if let session { words.append("session \(Int((shown(session) * 100).rounded())) %") }
        let dimmed = (age ?? 0) > dimAfter && week != nil
        return ClaudeRestReading(
            weekFill: week.map(shown),
            sessionText: session.map { AmbientFormat.percent(shown($0), step: 1) },
            isDimmed: dimmed,
            status: worst >= 0.9 ? .danger : worst >= 0.75 ? .warning : .neutral,
            label: "Claude, " + (words.isEmpty ? "limites inconnues" : words.joined(separator: ", ")) + (dimmed ? ", lecture ancienne" : ""))
    }
}

public enum ClaudeRest {
    public static let id = "claude.rest"

    /// The Claude indicator while nothing is working or waiting. Nil when there is nothing true to say: no number
    /// and no open session (a pending reading alone draws nothing, never a bare glyph).
    public static func indicator(reading: ClaudeRestReading?, sessionOpen: Bool) -> AmbientIndicator? {
        let numbers = reading?.hasNumbers == true
        guard numbers || sessionOpen else { return nil }
        let label = (reading?.label ?? "Claude") + (sessionOpen ? ", session ouverte" : "")
        return AmbientIndicator(
            id: id, channel: numbers ? AmbientChannel.limits : AmbientChannel.claude, symbol: ClaudeWing.restGlyph,
            text: reading?.sessionText, status: reading?.status ?? .neutral, progress: reading?.weekFill,
            wing: .leading, label: label, isDimmed: reading?.isDimmed ?? false,
            badge: sessionOpen ? .success : nil)
    }
}
