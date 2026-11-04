// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Mac Island calendar lane (Google Calendar through the macOS account). Hand-written, never touched by import.sh.

import Foundation

/// A video-call link found in an event, and the only kind the island ever opens: https, no credentials, the
/// default port, and a host that is (a subdomain of) one of five known providers. Event text is untrusted, so the
/// scan is bounded and the link is parsed, never executed or interpolated.
enum CalendarConferenceLink {
    static let allowedHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "webex.com", "whereby.com"]
    /// The longest link the island will open.
    static let maxLength = 2048
    /// Characters of a location or of notes that are read for a link; the rest is ignored.
    static let scanWindow = 8192

    /// The event's own URL field first, then its location, then its notes.
    static func detect(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, let checked = validated(url) { return checked }
        for text in [location, notes] {
            guard let text else { continue }
            for candidate in candidates(in: text) {
                if let url = URL(string: candidate), let checked = validated(url) { return checked }
            }
        }
        return nil
    }

    /// The URL itself when it passes every rule, otherwise nil. Called again on the click.
    static func validated(_ url: URL) -> URL? {
        let text = url.absoluteString
        guard text.utf8.count <= maxLength,
              !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control
                                                      || $0.properties.generalCategory == .format }),
              let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased(), !host.isEmpty,
              host.unicodeScalars.allSatisfy({ $0.isASCII }),
              allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              let result = parts.url else { return nil }
        return result
    }

    private static func candidates(in text: String) -> [String] {
        let window = String(text.utf8.prefix(scanWindow)) ?? String(text.prefix(scanWindow))
        var found: [String] = []
        var rest = Substring(window)
        while let range = rest.range(of: "https://", options: .caseInsensitive) {
            let tail = rest[range.lowerBound...]
            let end = tail.firstIndex { $0.isWhitespace || "<>\"'`\\".contains($0) } ?? tail.endIndex
            var link = String(tail[..<end])
            while let last = link.last, ".,;:!?)]}".contains(last) { link.removeLast() }
            found.append(link)
            rest = tail[tail.index(tail.startIndex, offsetBy: 8)...]
            if found.count >= 16 { break }
        }
        return found
    }
}

/// Event text is shown, never run. Control, format (bidi, zero width) and line-break characters go; the length is capped.
enum CalendarText {
    static func clean(_ text: String?, limit: Int) -> String {
        guard let text, limit > 0 else { return "" }
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars.prefix(limit * 8) {
            let category = scalar.properties.generalCategory
            if scalar == "\n" || scalar == "\r" || scalar == "\t" || category == .lineSeparator
                || category == .paragraphSeparator || scalar == "\u{85}" {
                pendingSpace = true
            } else if category == .control || category == .format || category == .surrogate
                        || category == .unassigned || category == .privateUse {
                continue
            } else {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            }
        }
        let trimmed = String(out).trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
    }
}

/// What EventKit says about one occurrence, as plain values.
struct CalendarEventRaw: Sendable {
    var title: String?
    var location: String?
    var notes: String?
    var url: URL?
    var cancelled: Bool
    var currentUserDeclined: Bool
}

/// The part of an event the island shows after the rules: nil when it is hidden.
struct CalendarEventFacts: Equatable, Sendable {
    static let maxTitle = 200
    static let maxLocation = 120
    /// Declined events are hidden unless this is on; cancelled ones always are. Not a Vorssaint key.
    static let showDeclinedKey = "macIslandCalendarShowDeclined"

    let title: String
    let location: String
    let joinURL: URL?
    let declined: Bool

    static func make(_ raw: CalendarEventRaw, showDeclined: Bool) -> CalendarEventFacts? {
        guard !raw.cancelled, showDeclined || !raw.currentUserDeclined else { return nil }
        return CalendarEventFacts(
            title: CalendarText.clean(raw.title, limit: maxTitle),
            location: CalendarText.clean(raw.location, limit: maxLocation),
            joinURL: CalendarConferenceLink.detect(url: raw.url, location: raw.location, notes: raw.notes),
            declined: raw.currentUserDeclined)
    }

    static func showsDeclined(in defaults: UserDefaults = PortHost.defaults) -> Bool {
        defaults.bool(forKey: showDeclinedKey)
    }
}
