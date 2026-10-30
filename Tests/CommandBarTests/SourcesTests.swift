import Foundation
import Testing
@testable import CommandBarFeature

@Suite struct SourcesTests {
    @Test func webSearchPercentEncodesEverythingUnsafe() throws {
        let url = try #require(WebSearchSource.url(for: "a b&c=d+e/é #1"))
        #expect(url.scheme == "https")
        #expect(url.host == "duckduckgo.com")
        #expect(url.absoluteString == "https://duckduckgo.com/?q=a%20b%26c%3Dd%2Be%2F%C3%A9%20%231")
    }

    @Test func webSearchRefusesEmpty() {
        #expect(WebSearchSource.url(for: "   ") == nil)
        #expect(WebSearchSource.url(for: "") == nil)
    }

    @Test func webSearchCapsTheQueryLength() throws {
        let url = try #require(WebSearchSource.url(for: String(repeating: "a", count: 5000)))
        #expect(url.absoluteString.count < 600)
    }

    @Test func fileSearchNeedsThreeCharacters() {
        #expect(!FileSource.isEligible(query: ""))
        #expect(!FileSource.isEligible(query: "ab"))
        #expect(!FileSource.isEligible(query: " a "))
        #expect(FileSource.isEligible(query: "abc"))
        #expect(FileSource.isEligible(query: " abc "))
        #expect(FileSource.maxResults == 20)
    }

    @Test func fileExclusions() {
        let home = "/Users/x"
        #expect(FileSource.isExcluded(path: "/Users/x/Library/Caches/a.txt", home: home))
        #expect(FileSource.isExcluded(path: "/Users/x/.ssh/id_rsa", home: home))
        #expect(FileSource.isExcluded(path: "/Users/x/proj/.git/config", home: home))
        #expect(FileSource.isExcluded(path: "/Users/x/proj/node_modules/a/b.js", home: home))
        #expect(!FileSource.isExcluded(path: "/Users/x/Documents/report.pdf", home: home))
    }

    @Test func fileResultsAreCappedAndOpenOrRevealTheFile() {
        let paths = (0..<50).map { "/Users/x/Documents/f\($0).txt" }
        let out = FileSource.makeResults(paths: paths, home: "/Users/x")
        #expect(out.count == 20)
        #expect(out[0].kind == .file)
        #expect(out[0].action == .open(URL(fileURLWithPath: paths[0])))
        #expect(out[0].reveal == URL(fileURLWithPath: paths[0]))
        #expect(out[0].title == "f0.txt")
    }

    @Test func appScanFindsBundlesAndNamesOnly() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Safari.app/Contents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Utilities/Terminal.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Safari.app/Contents/Inner.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Deep/A/B/Hidden.app"), withIntermediateDirectories: true)
        fm.createFile(atPath: root.appendingPathComponent("notes.txt").path, contents: Data())
        let apps = AppSource.scan(directories: [root, root.appendingPathComponent("missing")])
        #expect(apps.map(\.title).sorted() == ["Safari", "Terminal"])
        #expect(apps.allSatisfy { $0.kind == .app && $0.id.hasPrefix("app:") })
        let safari = try #require(apps.first { $0.title == "Safari" })
        // The temp dir is under /var, a symlink to /private/var: compare resolved paths.
        let expected = root.appendingPathComponent("Safari.app").resolvingSymlinksInPath().path
        #expect(safari.reveal?.resolvingSymlinksInPath().path == expected)
        if case .open(let url) = safari.action { #expect(url.resolvingSymlinksInPath().path == expected) } else { Issue.record("not open") }
    }

    @Test func defaultAppDirectoriesAreTheThreeStandardOnes() {
        let paths = AppSource.defaultDirectories.map(\.path)
        #expect(paths.contains("/Applications"))
        #expect(paths.contains("/System/Applications"))
        #expect(paths.contains { $0.hasSuffix("/Applications") && $0.hasPrefix(NSHomeDirectory()) })
    }

    @Test func calculatorSourceYieldsOneCopyResultOrNone() async throws {
        let src = CalculatorSource(locale: Locale(identifier: "en_US"))
        let hit = await src.results(for: "2+3*4")
        let r = try #require(hit.first)
        #expect(hit.count == 1)
        #expect(r.kind == .calculator)
        #expect(r.title == "= 14")
        #expect(r.action == .copy("14"))
        #expect(await src.results(for: "1/0").isEmpty)
        #expect(await src.results(for: "safari").isEmpty)
        #expect(await src.results(for: "42").isEmpty)
    }

    @Test func webSourceAlwaysOffersFallbackForNonEmptyQuery() async throws {
        let src = WebSearchSource()
        let r = try #require(await src.results(for: "swift ui").first)
        #expect(r.kind == .web)
        #expect(r.fixedScore != nil && r.fixedScore! < 0)
        #expect(await src.results(for: " ").isEmpty)
    }

    @Test @MainActor func commandRegistryMergesById() async {
        let reg = CommandRegistry()
        var ran = 0
        reg.register([BarCommand(id: "a", title: "Alpha", keywords: ["x"], run: { ran += 1 })])
        reg.register([BarCommand(id: "a", title: "Alpha 2", keywords: [], run: { ran += 10 }),
                      BarCommand(id: "b", title: "Beta", keywords: [], run: {})])
        #expect(reg.commands.map(\.title) == ["Alpha 2", "Beta"])
        reg.run(id: "a")
        #expect(ran == 10)
        reg.run(id: "missing")
        let items = await CommandSource(registry: reg).results(for: "")
        #expect(items.map(\.id) == ["cmd:a", "cmd:b"])
        #expect(items[0].kind == .command && items[0].action == .runCommand("a"))
    }
}
