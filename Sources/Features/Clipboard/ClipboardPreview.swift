import Foundation

/// The short text shown next to the menu bar icon: the newest copy on one line, never longer than the length the
/// person chose. Pure; it only ever sees what the history already recorded, so a concealed copy (never recorded)
/// cannot reach it.
enum ClipboardPreview {
    /// nil when nothing should show: the option is off, the history is off or empty, or the entry has no visible text.
    static func menuBarText(newest: ClipboardEntry?, enabled: Bool, length: Int) -> String? {
        guard enabled, let newest else { return nil }
        let raw: String
        switch newest.kind {
        case .text, .files: raw = newest.text
        case .image: raw = "Image"
        }
        return line(raw, limit: length)
    }

    /// Whitespace runs collapse to one space; a longer text ends with an ellipsis INSIDE the limit, so the result
    /// never has more than `limit` characters.
    static func line(_ raw: String, limit: Int) -> String? {
        let n = min(ClipboardSettings.menuBarPreviewLengthRange.upperBound,
                    max(ClipboardSettings.menuBarPreviewLengthRange.lowerBound, limit))
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= n { return collapsed }
        let head = String(collapsed.prefix(n - 1)).trimmingCharacters(in: .whitespaces)
        return head + "…"
    }
}
