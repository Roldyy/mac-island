// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit

struct NotchClipboardSizeStrings {
    let entrySize: String
    let compact: String
    let comfortable: String
    let hint: String
}

/// How tall a clipboard entry is on the island's page. Compact shows one or
/// two lines and opens up to the full entry when the pointer rests on it.
enum NotchClipboardCardSize: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }

    /// The size a stored value names. Anything else, nothing stored included,
    /// is comfortable: the entries the island showed before compact ones, so
    /// nobody gets the new layout without choosing it.
    init(stored: String?) {
        self = stored.flatMap(NotchClipboardCardSize.init(rawValue:)) ?? .comfortable
    }

    /// How long the pointer rests on a compact entry before it opens.
    static let dwell: TimeInterval = 0.7

    /// How long the arrow keys rest on a compact entry before it opens: longer
    /// than the pointer, since keys cross many entries on their way.
    static let keyDwell: TimeInterval = 1.4

    /// An entry opened to show its text goes up to this many lines, then ends in an ellipsis.
    static let maximumOpenLines = 8
    static let openLineHeight: CGFloat = 16
    /// What an open entry needs besides its content: padding, spacing and the row of actions.
    static let openChrome: CGFloat = 48
    static let maximumOpenImage: CGFloat = 170
    static let minimumOpenImage: CGFloat = 80

    /// The font an open entry draws its text in.
    static let openTextFont = NSFont.systemFont(ofSize: 12)

    /// Lines the text takes in `width`, measured in the entry's font, so wide
    /// glyphs such as Chinese, Japanese or Korean ones wrap as drawn.
    static func openLines(for text: String, width: CGFloat) -> Int {
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: openTextFont]).height
        let line = NSLayoutManager().defaultLineHeight(for: openTextFont)
        return min(maximumOpenLines, max(1, Int((measured / line).rounded(.up))))
    }

    /// The height of an open text entry, which shows as much of it as fits in a few lines.
    static func openHeight(text: String, width: CGFloat) -> CGFloat {
        CGFloat(openLines(for: text, width: width)) * openLineHeight + openChrome
    }

    private struct MeasuredText: Hashable {
        let id: UUID
        let text: String
        let width: CGFloat
    }
    private static var measuredOpenHeights: [MeasuredText: CGFloat] = [:]

    /// The same, measured once per entry, text and width, since the page reads
    /// the height on every layout. The history window can edit an entry's
    /// text, which keeps its id, so the text is part of what is measured.
    static func openHeight(text: String, width: CGFloat, id: UUID) -> CGFloat {
        let key = MeasuredText(id: id, text: text, width: width)
        if let height = measuredOpenHeights[key] { return height }
        // Entries come and go over days; a full cache starts again.
        if measuredOpenHeights.count >= 512 { measuredOpenHeights.removeAll() }
        let height = openHeight(text: text, width: width)
        measuredOpenHeights[key] = height
        return height
    }

    /// The height of an open image entry: the image at its own proportions, within a range.
    static func openHeight(aspectRatio: CGFloat?, width: CGFloat) -> CGFloat {
        let natural = max(1, width) / max(0.2, aspectRatio ?? 1.5)
        return min(maximumOpenImage, max(minimumOpenImage, natural)) + openChrome
    }

    static func current(in defaults: UserDefaults = PortHost.defaults) -> NotchClipboardCardSize {
        NotchClipboardCardSize(stored: defaults.string(forKey: DefaultsKey.notchClipboardCardSize))
    }
}

extension FeatureStrings {
    static func notchClipboardSize(_ language: AppLanguage) -> NotchClipboardSizeStrings {
        switch language {
        case .enUS: return NotchClipboardSizeStrings(
            entrySize: "Entry size",
            compact: "Compact",
            comfortable: "Comfortable",
            hint: "Compact entries show one or two lines and open up when the pointer rests on them.")
        default: return NotchClipboardSizeStrings(
            entrySize: "Taille des entrées",
            compact: "Compacte",
            comfortable: "Confortable",
            hint: "Les entrées compactes montrent une ou deux lignes et s’agrandissent quand le pointeur s’y arrête.")
        }
    }
}
