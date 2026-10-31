import Foundation
import Testing

@Suite struct DesignLintTests {
    /// W1 re-skins the existing modules; until it lands the repo-wide run only reports.
    /// Flip to `true` once the tree is clean and the lint becomes a gate.
    static let enforce = false

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func rules(_ source: String) -> [String] {
        DesignLint.scan(source: source, file: "x.swift").map(\.rule)
    }

    // MARK: the lint itself (always enforced)

    @Test func flagsSmallFonts() {
        #expect(rules(#"Text("a").font(.system(size: 10))"#) == ["police-trop-petite"])
        #expect(rules(#"Text("a").font(.system(size: 9, weight: .bold))"#) == ["police-trop-petite"])
        #expect(rules(#"Text("a").font(.system(size: 10.5))"#) == ["police-trop-petite"])
        #expect(rules(#"Text("a").font(.caption2)"#) == ["police-systeme-caption2"])
    }

    @Test func allowsLegalFonts() {
        #expect(rules(#"Text("a").font(.system(size: 11))"#).isEmpty)
        #expect(rules(#"Text("a").font(.system(size: 13, weight: .semibold))"#).isEmpty)
        #expect(rules(#"Text("a").font(.system(size: 100))"#).isEmpty)
        #expect(rules(#"Text("a").font(.islandCaption)"#).isEmpty)
    }

    @Test func flagsRawStatusColors() {
        #expect(rules("Circle().fill(.red)") == ["couleur-brute-statut"])
        #expect(rules("Text(\"a\").foregroundStyle(.green)") == ["couleur-brute-statut"])
        #expect(rules("let c = Color.orange") == ["couleur-brute-statut"])
        #expect(rules("let c = Color(red: 1, green: 0, blue: 0)") == ["couleur-litterale"])
        #expect(rules("let c = NSColor.systemRed") == ["couleur-brute-statut"])
        #expect(rules("Text(\"a\").foregroundStyle(IslandPalette.statusDanger.color)").isEmpty)
        #expect(rules("Text(\"a\").foregroundStyle(.secondary)").isEmpty)
    }

    @Test func flagsDirectControlStyles() {
        #expect(rules("Button(\"Go\") {}.buttonStyle(.bordered)") == ["style-bouton-direct"])
        #expect(rules("Button(\"Go\") {}.buttonStyle(.borderedProminent)") == ["style-bouton-direct"])
        #expect(rules("Toggle(\"a\", isOn: $x).toggleStyle(.switch)") == ["style-interrupteur-direct"])
        #expect(rules("Button(\"Go\") {}.buttonStyle(IslandButtonStyle())").isEmpty)
        #expect(rules("Button(\"Go\") {}.buttonStyle(.island)").isEmpty)
    }

    @Test func flagsEnglishUIStrings() {
        #expect(rules(#"Button("Cancel") {}"#) == ["texte-anglais"])
        #expect(rules(#"Text("Settings")"#) == ["texte-anglais"])
        #expect(rules(#"Button("Clear", action: clear)"#) == ["texte-anglais"])
        #expect(rules(#"Button("Annuler") {}"#).isEmpty)
        #expect(rules(#"let key = "Settings""#).isEmpty)
    }

    @Test func ignoresWholeLineComments() {
        #expect(rules("// Text(\"Settings\").font(.system(size: 9))").isEmpty)
        #expect(rules("    /// foregroundStyle(.red) is forbidden").isEmpty)
    }

    @Test func reportsFileAndLine() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mis-lint-\(UUID().uuidString)")
        let folder = dir.appendingPathComponent("Sources/Features/X")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "import SwiftUI\nText(\"a\").font(.system(size: 9))\n".write(
            to: folder.appendingPathComponent("V.swift"), atomically: true, encoding: .utf8)
        let violations = DesignLint.scan(root: dir)
        #expect(violations.count == 1)
        #expect(violations.first?.file == "Sources/Features/X/V.swift")
        #expect(violations.first?.line == 2)
    }

    @Test func missingFoldersAreSkipped() {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("mis-absent-\(UUID().uuidString)")
        #expect(DesignLint.scan(root: nowhere).isEmpty)
    }

    // MARK: the repo (report-only until W1)

    @Test func repositoryFollowsTheDesignSystem() {
        let violations = DesignLint.scan(root: Self.repoRoot)
        if !violations.isEmpty {
            print("DesignLint : \(violations.count) violation(s), enforce = \(Self.enforce)")
            for violation in violations.prefix(200) { print("  \(violation)") }
        }
        if Self.enforce {
            #expect(violations.isEmpty, "\(violations.count) violation(s) du système de design")
        }
    }
}
