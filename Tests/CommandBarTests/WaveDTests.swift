import AppKit
import Foundation
import Testing
@testable import CommandBarFeature

/// Answers differently per query, like real sources do.
private struct QuerySource: ResultSource {
    let sourceID = "apps"
    let byQuery: [String: [BarResult]]
    func results(for query: String) async -> [BarResult] { byQuery[query] ?? [] }
}

@MainActor private final class OpenSpy {
    var opened: [URL] = []
    var actions: BarActions {
        BarActions(open: { self.opened.append($0) }, reveal: { _ in }, copy: { _ in }, runCommand: { _ in })
    }
}

@Suite final class WaveDTests {
    let bag = DefaultsBag()

    private func app(_ name: String) -> BarResult {
        let url = URL(fileURLWithPath: "/Applications/\(name).app")
        return BarResult(id: "app:\(url.path)", title: name, subtitle: "Application", kind: .app,
                         action: .open(url), reveal: url)
    }

    // Fix 3: Return during the debounce must act on the current query, not the previous rows.
    @Test @MainActor func submitRefreshesAStaleQueryBeforeActivating() async {
        let spy = OpenSpy()
        let source = QuerySource(byQuery: ["ma": [app("Mail")], "sa": [app("Safari")]])
        let settings = CommandBarSettings(defaults: bag.makeDefaults())
        let m = CommandBarModel(sources: [source], habits: HabitStore(directory: makeTempDir()),
                                settings: { settings }, actions: spy.actions)
        m.query = "ma"
        await m.refresh()
        #expect(m.results.first?.title == "Mail")
        m.query = "sa"                         // typed, debounce still pending
        #expect(await m.submit(reveal: false))
        #expect(spy.opened == [URL(fileURLWithPath: "/Applications/Safari.app")])
    }

    @Test @MainActor func submitDoesNotRefreshWhenResultsAreCurrent() async {
        let spy = OpenSpy()
        let source = QuerySource(byQuery: ["sa": [app("Safari")]])
        let settings = CommandBarSettings(defaults: bag.makeDefaults())
        let m = CommandBarModel(sources: [source], habits: HabitStore(directory: makeTempDir()),
                                settings: { settings }, actions: spy.actions)
        m.query = "sa"
        await m.refresh()
        #expect(await m.submit(reveal: false))
        #expect(spy.opened.count == 1)
    }

    // Fix 5: Finder lives outside the scanned folders.
    @Test func extraBundlesAreScannedWhenTheyExistOnly() {
        let root = makeTempDir()
        let extra = root.appendingPathComponent("Finder.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("Nope.app", isDirectory: true)
        let apps = AppSource.scan(directories: [root], extraBundles: [extra, missing])
        #expect(apps.filter { $0.title == "Finder" }.count == 1)   // also found by the folder walk: no duplicate
        let alone = AppSource.scan(directories: [], extraBundles: [extra, missing])
        #expect(alone.map(\.title) == ["Finder"])
    }

    @Test func defaultScanIncludesFinderFromCoreServices() {
        #expect(AppSource.defaultExtraBundles.map(\.path) == ["/System/Library/CoreServices/Finder.app"])
    }

    // Fix 4: above the open island (NotchPanel uses .screenSaver).
    @Test @MainActor func barSitsAboveTheIslandPanel() {
        let panel = CommandBarPanel()
        #expect(panel.level.rawValue > NSWindow.Level.screenSaver.rawValue)
    }

    // Fix 2: documents that key codes are ANSI positions, not labels.
    @Test func hotkeyKeysArePhysicalAnsiPositions() throws {
        #expect(try #require(HotkeySpec.parse("option+command:a")).keyCode == 0)
        #expect(try #require(HotkeySpec.parse("option+command:q")).keyCode == 12)  // AZERTY: the key labelled "a"
    }
}
