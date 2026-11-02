import IslandUI
import SwiftUI

/// What the preview card shows, as plain data (so it can be checked without drawing).
struct TerminalColorProfilePreviewContent: Equatable {
    struct Swatch: Equatable, Identifiable {
        var id: String { label }
        var label: String
        var hex: String
        var color: TerminalRGB
        var accessibilityLabel: String { "\(label) : \(hex)" }
    }

    static let ansiNames = ["Noir", "Rouge", "Vert", "Jaune", "Bleu", "Magenta", "Cyan", "Blanc"]

    var name: String
    var summary: String
    var fontLine: String?
    var ansi: [Swatch]
    var special: [Swatch]

    init(_ entry: TerminalColorProfileImport) { self.init(entry.profile, foundColors: entry.foundColors) }

    init(_ profile: TerminalColorProfile, foundColors: Int? = nil) {
        name = profile.name
        if let foundColors {
            summary = "\(foundColors) couleur\(foundColors > 1 ? "s" : "") lue\(foundColors > 1 ? "s" : "") sur \(TerminalColorProfileImport.totalColors) ; les autres viennent du thème actuel."
        } else {
            summary = ""
        }
        fontLine = profile.fontName.map { name in
            profile.fontSize.map { "Police du profil : \(name) \(Int($0)) pt (utilisée si elle est installée, taille inchangée)" }
                ?? "Police du profil : \(name)"
        }
        ansi = profile.ansi.enumerated().map { index, color in
            let base = Self.ansiNames[index % 8]
            return Swatch(label: index < 8 ? "\(base) (ANSI \(index))" : "\(base) vif (ANSI \(index))", hex: color.hex, color: color)
        }
        special = [
            Swatch(label: "Texte", hex: profile.foreground.hex, color: profile.foreground),
            Swatch(label: "Fond", hex: profile.background.hex, color: profile.background),
            Swatch(label: "Curseur", hex: profile.cursor.hex, color: profile.cursor),
            Swatch(label: "Sélection", hex: profile.selection.hex, color: profile.selection),
        ]
    }
}

/// Swatches of the 16 ANSI colours and of text, background, cursor and selection, under the profile name.
struct TerminalColorProfilePreview: View {
    let content: TerminalColorProfilePreviewContent

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader(content.name, subtitle: content.summary.isEmpty ? nil : content.summary)
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: IslandSpacing.xs) {
                            ForEach(Array(content.ansi[(row * 8)..<(row * 8 + 8)])) { swatch in
                                SwatchView(swatch: swatch, size: 26)
                            }
                        }
                    }
                }
                HStack(spacing: IslandSpacing.m) {
                    ForEach(content.special) { swatch in
                        HStack(spacing: IslandSpacing.xs) {
                            SwatchView(swatch: swatch, size: 22)
                            Text(swatch.label).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                        }
                    }
                }
                if let fontLine = content.fontLine {
                    Text(fontLine).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aperçu du profil de couleurs \(content.name)")
    }

    private struct SwatchView: View {
        let swatch: TerminalColorProfilePreviewContent.Swatch
        let size: CGFloat

        var body: some View {
            RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous)
                .fill(swatch.color.swiftUIColor)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous)
                        .strokeBorder(IslandPalette.separatorStrong.color, lineWidth: 0.5)
                }
                .help("\(swatch.label) : \(swatch.hex)")
                .accessibilityElement()
                .accessibilityLabel(swatch.accessibilityLabel)
        }
    }
}
