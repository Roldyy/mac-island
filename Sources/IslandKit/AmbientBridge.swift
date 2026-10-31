import Foundation
import IslandUI

/// Turns what the activity engine resolved (one item per wing) into indicators, so Claude, the limits gauge,
/// the music wing and the alerts reach the closed island through `ActivityCenter` as before. Pure.
///
/// The arbiter has already kept one item per wing, ranked by priority, so what arrives here is what won.
public enum AmbientBridge {
    static let limitsSymbol = "gauge"
    /// A solid star reads at 9 pt inside the ring; the gauge dial does not.
    static let limitsGlyph = "sparkle"
    static let musicNoteSymbol = "music.note"
    static let musicWaveSymbol = "waveform"
    static let folderSymbol = "folder"

    public static func indicators(from layout: ActivityLayout, claude: ClaudeWorkSample?) -> [AmbientIndicator] {
        var out: [AmbientIndicator] = []
        var leading = layout.leading, trailing = layout.trailing

        if ClaudeWing.isClaudeWing(leading), let item = leading {
            let waiting = item.status == .warning
            out.append(AmbientIndicator(
                id: "claude", channel: AmbientChannel.claude, symbol: item.symbol, status: item.status,
                priority: waiting ? .claudeWaiting : .claudeWorking, isUrgent: waiting, wing: .leading,
                isBusy: !waiting, clockSince: claude?.since,
                label: waiting ? "Claude attend" : "Claude travaille"))
            leading = nil
            // Older posts carried the folder name on the other wing; the clock replaces it.
            if trailing?.symbol == folderSymbol { trailing = nil }
        }

        if let wave = trailing, wave.symbol == musicWaveSymbol {
            let progress = leading?.symbol == musicNoteSymbol ? leading?.progress : nil
            let title = wave.text.flatMap { $0.isEmpty ? nil : $0 }
            out.append(AmbientIndicator(
                id: "music", channel: AmbientChannel.music, symbol: musicWaveSymbol, text: title,
                progress: progress, priority: .music, wing: .trailing, glyph: .equalizer,
                label: title.map { "Lecture : \($0)" } ?? "Lecture en cours"))
            trailing = nil
            if leading?.symbol == musicNoteSymbol { leading = nil }
        } else if let note = leading, note.symbol == musicNoteSymbol {
            out.append(AmbientIndicator(
                id: "music", channel: AmbientChannel.music, symbol: musicWaveSymbol, progress: note.progress,
                priority: .music, wing: .trailing, glyph: .equalizer, label: "Lecture en cours"))
            leading = nil
        }

        if let gauge = leading, gauge.symbol == limitsSymbol {
            out.append(AmbientIndicator(
                id: "limits", channel: AmbientChannel.limits, symbol: limitsGlyph, text: gauge.text,
                status: gauge.status, progress: gauge.progress, wing: .leading, label: "Limite Claude"))
            leading = nil
        }

        // Anything else was posted as an alert (cleaning countdown, quick-access notice).
        for (index, item) in [leading, trailing].enumerated() {
            guard let item else { continue }
            let (text, label) = shortened(item.text)
            out.append(AmbientIndicator(
                id: "alert.\(index)", channel: AmbientChannel.alert, symbol: item.symbol.isEmpty ? item.status.symbol : item.symbol,
                text: text, status: item.status, progress: item.progress, priority: .alert,
                isUrgent: item.status == .warning || item.status == .danger,
                wing: index == 0 ? .leading : .trailing, label: label))
        }
        return out
    }

    /// "Nettoyage : 45 s" shows "45 s" and keeps the whole sentence for VoiceOver: a wing has no room for a
    /// sentence, and the glyph already says what it is about.
    static func shortened(_ text: String?) -> (text: String?, label: String?) {
        guard let text, !text.isEmpty else { return (nil, nil) }
        guard text.count > 10, let range = text.range(of: " : ", options: .backwards) else { return (text, nil) }
        let tail = String(text[range.upperBound...])
        return tail.isEmpty ? (text, nil) : (tail, text)
    }
}
