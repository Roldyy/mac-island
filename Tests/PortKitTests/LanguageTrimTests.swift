import Foundation
import Testing
@testable import PortKit

/// Lane W9D: the UI of the port is French (English stays as the base table); the 13 other languages of the reference app
/// are gone from the sources, and no table names the brand of the reference app.
@MainActor
@Suite struct LanguageTrimTests {
    static let dropped = ["ptBR", "tr", "ru", "es", "sk", "de", "it", "ja", "ko", "uk", "zhHans", "zhTW", "zhHK"]

    private var swiftFiles: [(path: String, text: String)] {
        let root = PortSourceScrubTests.portKit
        var result: [(String, String)] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return result }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) { result.append((url.path, text)) }
        }
        return result
    }

    @Test func noTableOfADroppedLanguageRemains() throws {
        let regex = try NSRegularExpression(pattern: "^\\s*static let (\(Self.dropped.joined(separator: "|")))\\s*=", options: [.anchorsMatchLines])
        var offenders: [String] = []
        for file in swiftFiles {
            let range = NSRange(file.text.startIndex..., in: file.text)
            if regex.firstMatch(in: file.text, range: range) != nil { offenders.append(file.path) }
        }
        #expect(offenders.isEmpty, "tables left: \(offenders.prefix(5))")
    }

    @Test func noCaseOfADroppedLanguageRemains() throws {
        let regex = try NSRegularExpression(pattern: "^\\s*case \\.(\(Self.dropped.joined(separator: "|")))\\b", options: [.anchorsMatchLines])
        var offenders: [String] = []
        for file in swiftFiles {
            for line in file.text.split(separator: "\n") where !line.contains(".fr") {  // a group that also names French is the catch-all
                if regex.firstMatch(in: String(line), range: NSRange(location: 0, length: line.utf16.count)) != nil {
                    offenders.append(file.path)
                    break
                }
            }
        }
        #expect(offenders.isEmpty, "cases left: \(offenders.prefix(5))")
    }

    @Test func frenchIsTheOnlyLanguageShown() {
        L10n.shared.language = .ja  // the pin turns it back
        #expect(L10n.shared.language == .fr)
        // A language with no table reads French, never a crash and never a blank.
        #expect(Strings.localized(.de).menuBarSection == Strings.localized(.fr).menuBarSection)
        #expect(Strings.localized(.zhHK).menuBarSection == "Barre des menus")
    }

    @Test func noStringOfTheBaseTablesNamesTheReferenceBrand() {
        for language in [AppLanguage.fr, .enUS] {
            let strings = Strings.localized(language)
            for child in Mirror(reflecting: strings).children {
                guard let text = child.value as? String else { continue }
                #expect(!text.localizedCaseInsensitiveContains("vorssaint"), "\(language.rawValue).\(child.label ?? "?")")
            }
        }
    }

    @Test func theTrimIsAScriptThatCanRunAgain() {
        let script = PortSourceScrubTests.repoRoot.appendingPathComponent("scripts/port/trim-languages.py")
        #expect(FileManager.default.fileExists(atPath: script.path))
    }
}
