import Foundation
import Testing

/// Source-level gates on Sources/PortKit: header, brand, hosts. They read the files by path, like the
/// upstream tests do, so a re-import that brings a Vorssaint host back fails here.
@Suite struct PortSourceScrubTests {
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static var portKit: URL { repoRoot.appendingPathComponent("Sources/PortKit") }

    /// Every Swift file of the port: (path relative to Sources/PortKit, lines).
    static let files: [(path: String, lines: [Substring])] = {
        let root = portKit
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var result: [(String, [Substring])] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result.append((relative, text.split(separator: "\n", omittingEmptySubsequences: false)))
        }
        return result
    }()

    static let derivedLine = "// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island."

    @Test func theImportIsPresent() {
        #expect(Self.files.count > 600)
    }

    @Test func everyCopiedFileCarriesTheDerivedHeader() {
        let copied = Self.files.filter { !$0.path.hasPrefix("Bridge/") }
        let missing = copied.filter { !$0.lines.prefix(6).contains { $0 == Self.derivedLine[...] } }.map(\.path)
        #expect(missing.isEmpty, "no Derived header: \(missing.prefix(5))")
    }

    @Test func noVorssaintWordInCodeLines() {
        // Comments may credit the origin; code and string literals may not carry the brand as a word.
        var offenders: [String] = []
        for file in Self.files {
            for (index, line) in file.lines.enumerated() {
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if trimmed.hasPrefix("//") { continue }
                if line.range(of: #"\bVorssaint\b"#, options: .regularExpression) != nil {
                    offenders.append("\(file.path):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "brand left in code: \(offenders.prefix(5))")
    }

    @Test func noVorssaintHostIsReachable() {
        let banned = ["vorssaint.com", "screenshots.vorssaint", "3D485NHW29", "buymeacoffee", "discord.gg",
                      "github.com/vorssaint", "raw.githubusercontent.com/vorssaint", "x.com/vorssaint"]
        var offenders: [String] = []
        for file in Self.files {
            for (index, line) in file.lines.enumerated() {
                if banned.contains(where: { line.contains($0) }) { offenders.append("\(file.path):\(index + 1)") }
            }
        }
        #expect(offenders.isEmpty, "external host: \(offenders.prefix(5))")
    }

    /// `com.vorssaint` survives only where the code must recognise the old app: the five self-exclusion checks,
    /// one code line each (a second line in any of them, or a new file, is an identifier that should have been
    /// rewritten). Every one of those files must also name our own id next to it (patch 0010).
    @Test func comVorssaintOnlyInLegacyRecognition() {
        let allowed: [String: Int] = [
            "Services/DockClick/DockClickSupport.swift": 1, "Services/Uninstall/UninstallerSupport.swift": 1,
            "Services/Cleaner/CleanerPolicy.swift": 1, "Services/Cleaner/CleanerSupport.swift": 1,
            "Services/AppUpdates/AppUpdatesService.swift": 1,
        ]
        var offenders: [String] = []
        for file in Self.files {
            var count = 0
            for (index, line) in file.lines.enumerated() where line.contains("com.vorssaint") {
                if line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") { continue }
                count += 1
                if allowed[file.path] == nil || count > allowed[file.path]! { offenders.append("\(file.path):\(index + 1)") }
            }
            if let expected = allowed[file.path], count != expected {
                offenders.append("\(file.path): expected \(expected) legacy line(s), found \(count)")
            }
            if allowed[file.path] != nil, !file.lines.contains(where: { $0.contains("be.roldy.macisland") }) {
                offenders.append("\(file.path): own bundle id not protected")
            }
        }
        #expect(offenders.isEmpty, "unrewritten identifier: \(offenders.prefix(5))")
    }

    /// Case-insensitive, comments included: no handle of the old author may survive (the "Follow @vorssaint on X"
    /// strings were removed by patch 0011).
    @Test func noVorssaintHandleAnywhere() {
        var offenders: [String] = []
        for file in Self.files {
            for (index, line) in file.lines.enumerated() where line.lowercased().contains("@vorssaint") {
                offenders.append("\(file.path):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, "old author handle: \(offenders.prefix(5))")
    }

    /// The Now Playing adapter is built as `libMacIslandNowPlaying.dylib` (Package.swift). Every `.dylib` name the
    /// port can resolve must be that one: the radial menu once kept upstream's `libVorssaintNowPlaying.dylib`,
    /// which does not exist in our bundle, so its Now Playing card was always empty.
    @Test func everyAdapterLibraryNameTheAppResolvesIsOurs() throws {
        var names = Set<String>()
        var radialUsesLocator = false
        for file in Self.files {
            for line in file.lines {
                var rest = Substring(line)
                while let range = rest.range(of: ".dylib") {
                    let head = rest[..<range.lowerBound]
                    let start = head.lastIndex(where: { !($0.isLetter || $0.isNumber) }).map { head.index(after: $0) }
                        ?? head.startIndex
                    names.insert(String(head[start...]) + ".dylib")
                    rest = rest[range.upperBound...]
                }
            }
            if file.path == "Services/RadialMenu/RadialNowPlayingService.swift" {
                radialUsesLocator = file.lines.contains { $0.contains("MediaRemoteAdapterLocator.live.launchArguments()") }
            }
        }
        #expect(names == ["libMacIslandNowPlaying.dylib"], "adapter library names in the port: \(names.sorted())")
        #expect(radialUsesLocator, "the radial menu resolves the adapter through MediaRemoteAdapterLocator (patch 1800)")
        let package = try String(contentsOf: Self.repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(package.contains(".library(name: \"MacIslandNowPlaying\", type: .dynamic"))
        let patches = try FileManager.default.contentsOfDirectory(
            atPath: Self.repoRoot.appendingPathComponent("scripts/port/patches").path)
        #expect(patches.contains("1800-radial-now-playing-uses-adapter-locator.patch"))
    }

    @Test func defaultsKeyNamesAreKeptVerbatim() throws {
        let url = Self.portKit.appendingPathComponent("Core/Defaults.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        for key in ["screenshotHideVorssaintWindows", "showReleaseNotesBeforeUpdate", "clipboardHistoryEnabled"] {
            #expect(text.contains("\"\(key)\""), "\(key) was rewritten")
        }
    }

    /// The private-API surface is an allowlist: a new `dlopen` / `dlsym` / `@_silgen_name` site fails here
    /// until someone reads it and adds it.
    @Test func privateSymbolSitesAreKnown() throws {
        let known = try String(contentsOf: Self.repoRoot.appendingPathComponent("scripts/port/private-api-allowlist.txt"),
                               encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }
        var found = Set<String>()
        for file in Self.files where !file.path.hasPrefix("Compat/") {
            if file.lines.contains(where: { $0.contains("dlopen(") || $0.contains("dlsym(") || $0.contains("@_silgen_name") }) {
                found.insert(file.path)
            }
        }
        let unknown = found.subtracting(known).sorted()
        #expect(unknown.isEmpty, "new private-API file: \(unknown)")
    }
}
