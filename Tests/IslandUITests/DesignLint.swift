import Foundation

struct DesignLintViolation: Equatable, CustomStringConvertible {
    let file: String
    let line: Int
    let rule: String
    let excerpt: String

    var description: String { "\(file):\(line) [\(rule)] \(excerpt)" }
}

/// Source scanner behind DesignLintTests. Pure: a root directory in, violations out.
enum DesignLint {
    /// Folders of the app that must follow the design system (IslandUI itself defines it).
    static let scannedFolders = [
        "Sources/Features", "Sources/MacIsland", "Sources/ShellKit", "Sources/IslandKit",
        // The ported Vorssaint code keeps its own look until each lane re-skins its pages: report-only.
        "Sources/PortKit",
    ]

    static let englishWords = [
        "Settings", "Cancel", "Clear", "Close", "Delete", "Quit", "Save", "Done", "Loading", "Enable", "Disable", "Reset",
    ]

    private struct Rule {
        let name: String
        let regex: NSRegularExpression
    }

    private static func rule(_ name: String, _ pattern: String) -> Rule {
        // Patterns are literals in this file; a typo must fail loudly in the tests.
        guard let regex = try? NSRegularExpression(pattern: pattern) else { fatalError("motif invalide : \(pattern)") }
        return Rule(name: name, regex: regex)
    }

    private static let rules: [Rule] = [
        rule("police-trop-petite", #"\.system\(\s*size:\s*(?:[0-9]|10)(?:\.[0-9]+)?\s*[,)]"#),
        rule("police-systeme-caption2", #"\.caption2\b"#),
        rule("couleur-brute-statut", #"(?:\bColor\.|\bNSColor\.system|\.foreground(?:Style|Color)\(\s*\.|\.fill\(\s*\.|\.tint\(\s*\.)(?:red|green|orange|yellow|cyan|Red|Green|Orange|Yellow)\b"#),
        rule("couleur-litterale", #"\bColor\(\s*(?:red:|\.sRGB|\.displayP3)"#),
        rule("style-bouton-direct", #"\.buttonStyle\(\s*\.(?:bordered|borderedProminent|borderless|link)\b"#),
        rule("style-interrupteur-direct", #"\.toggleStyle\(\s*\.(?:switch|button|checkbox)\b"#),
        rule("texte-anglais", "(?:Text|Button|Label|Toggle|Section|Picker|Menu|TextField|Link|\\.help|\\.navigationTitle|\\.accessibilityLabel)\\(\\s*\"(?:\(englishWords.joined(separator: "|")))\""),
    ]

    /// Violations in one source text. Whole-line comments are skipped.
    static func scan(source: String, file: String) -> [DesignLintViolation] {
        var found: [DesignLintViolation] = []
        for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let text = String(line)
            if text.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(text.startIndex..., in: text)
            for rule in rules where rule.regex.firstMatch(in: text, range: range) != nil {
                found.append(DesignLintViolation(
                    file: file, line: index + 1, rule: rule.name,
                    excerpt: text.trimmingCharacters(in: .whitespaces)))
            }
        }
        return found
    }

    /// Violations in every `.swift` file under `root/<folder>` for each folder given.
    static func scan(root: URL, folders: [String] = scannedFolders) -> [DesignLintViolation] {
        var found: [DesignLintViolation] = []
        let root = root.resolvingSymlinksInPath()  // /var vs /private/var in temp directories
        for folder in folders {
            let base = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
            for url in files {
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let resolved = url.resolvingSymlinksInPath().path
                let relative = resolved.hasPrefix(root.path + "/") ? String(resolved.dropFirst(root.path.count + 1)) : resolved
                found += scan(source: source, file: relative)
            }
        }
        return found
    }
}
