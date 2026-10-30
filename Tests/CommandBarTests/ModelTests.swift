import Foundation
import Testing
@testable import CommandBarFeature

@MainActor
private final class Spy {
    var opened: [URL] = []
    var revealed: [URL] = []
    var copied: [String] = []
    var commands: [String] = []
    var actions: BarActions {
        BarActions(open: { self.opened.append($0) }, reveal: { self.revealed.append($0) },
                   copy: { self.copied.append($0) }, runCommand: { self.commands.append($0) })
    }
}

@Suite final class ModelTests {
    let bag = DefaultsBag()

    @MainActor private func make(_ sources: [any ResultSource], spy: Spy, defaults: UserDefaults? = nil,
                                 dir: URL = makeTempDir()) -> (CommandBarModel, HabitStore, CommandBarSettings) {
        let settings = CommandBarSettings(defaults: defaults ?? bag.makeDefaults())
        let habits = HabitStore(directory: dir)
        return (CommandBarModel(sources: sources, habits: habits, settings: { settings }, actions: spy.actions),
                habits, settings)
    }

    private func appItem(_ name: String) -> BarResult {
        let url = URL(fileURLWithPath: "/Applications/\(name).app")
        return BarResult(id: "app:\(url.path)", title: name, subtitle: "Application", kind: .app,
                         action: .open(url), reveal: url)
    }

    @Test @MainActor func enterRunsTopResultAndRecordsHabit() async {
        let spy = Spy()
        let (m, habits, _) = make([StubSource(sourceID: "apps", items: [appItem("Safari"), appItem("Mail")])], spy: spy)
        m.query = "saf"
        await m.refresh()
        #expect(m.results.first?.title == "Safari")
        #expect(m.activate(reveal: false))
        #expect(spy.opened == [URL(fileURLWithPath: "/Applications/Safari.app")])
        #expect(habits.weight("app:/Applications/Safari.app", now: Date()) > 0.9)
    }

    @Test @MainActor func arrowsMoveAndClamp() async {
        let spy = Spy()
        let (m, _, _) = make([StubSource(sourceID: "apps", items: [appItem("Alpha"), appItem("Alps"), appItem("Alto")])], spy: spy)
        m.query = "al"
        await m.refresh()
        #expect(m.selectedIndex == 0)
        m.move(1); m.move(1); m.move(1); m.move(1)
        #expect(m.selectedIndex == m.results.count - 1)
        m.move(-1)
        #expect(m.selectedIndex == m.results.count - 2)
        for _ in 0..<10 { m.move(-1) }
        #expect(m.selectedIndex == 0)
        m.move(1)
        #expect(m.activate(reveal: false))
        #expect(spy.opened.count == 1 && spy.opened[0].lastPathComponent != "")
    }

    @Test @MainActor func commandEnterRevealsInFinderOnlyWhenPossible() async {
        let spy = Spy()
        let cmd = BarResult(id: "cmd:x", title: "Do X", kind: .command, action: .runCommand("x"))
        let (m, _, _) = make([StubSource(sourceID: "apps", items: [appItem("Safari")]),
                              StubSource(sourceID: "commands", items: [cmd])], spy: spy)
        m.query = "safari"
        await m.refresh()
        #expect(m.activate(reveal: true))
        #expect(spy.revealed == [URL(fileURLWithPath: "/Applications/Safari.app")])
        #expect(spy.opened.isEmpty)
        m.query = "do x"
        await m.refresh()
        #expect(m.results.first?.id == "cmd:x")
        #expect(!m.activate(reveal: true))                   // nothing to reveal for a command
        #expect(spy.commands.isEmpty)
        #expect(m.activate(reveal: false))
        #expect(spy.commands == ["x"])
    }

    @Test @MainActor func calculatorFirstWebLastAndCopyAction() async {
        let spy = Spy()
        let sources: [any ResultSource] = [CalculatorSource(locale: Locale(identifier: "en_US")),
                                           WebSearchSource(),
                                           StubSource(sourceID: "apps", items: [appItem("Calc 2")])]
        let (m, _, _) = make(sources, spy: spy)
        m.query = "2+2"
        await m.refresh()
        #expect(m.results.first?.kind == .calculator)
        #expect(m.results.last?.kind == .web)
        #expect(m.activate(reveal: false))
        #expect(spy.copied == ["4"])
        #expect(spy.opened.isEmpty)
    }

    @Test @MainActor func webFallbackOpensEncodedURL() async {
        let spy = Spy()
        let (m, _, _) = make([WebSearchSource()], spy: spy)
        m.query = "hello world"
        await m.refresh()
        #expect(m.results.count == 1)
        #expect(m.activate(reveal: false))
        #expect(spy.opened.first?.absoluteString == "https://duckduckgo.com/?q=hello%20world")
    }

    @Test @MainActor func disabledSourcesAreSkipped() async {
        let spy = Spy()
        let (m, _, settings) = make([StubSource(sourceID: "apps", items: [appItem("Safari")]), WebSearchSource()], spy: spy)
        settings.setSource("web", enabled: false)
        m.query = "saf"
        await m.refresh()
        #expect(m.results.map(\.title) == ["Safari"])
        settings.setSource("apps", enabled: false)
        await m.refresh()
        #expect(m.results.isEmpty)
        #expect(!m.activate(reveal: false))
    }

    @Test @MainActor func slowSourcesAreMergedAfterFastOnes() async {
        let spy = Spy()
        let file = BarResult(id: "file:/a/safari-notes.txt", title: "safari-notes.txt", kind: .file,
                             action: .open(URL(fileURLWithPath: "/a/safari-notes.txt")),
                             reveal: URL(fileURLWithPath: "/a/safari-notes.txt"))
        let (m, _, _) = make([StubSource(sourceID: "apps", items: [appItem("Safari")]),
                              StubSource(sourceID: "files", isSlow: true, items: [file])], spy: spy)
        m.query = "safari"
        await m.refresh()
        #expect(m.results.map(\.kind) == [.app, .file])
    }

    @Test @MainActor func habitsOffMeansNoRecordingAndNoBoost() async {
        let spy = Spy()
        let (m, habits, settings) = make([StubSource(sourceID: "apps", items: [appItem("Notes"), appItem("Notion")])], spy: spy)
        habits.record("app:/Applications/Notion.app")
        habits.record("app:/Applications/Notion.app")
        m.query = "not"
        await m.refresh()
        #expect(m.results.first?.title == "Notion")
        settings.habitsEnabled = false
        await m.refresh()
        #expect(m.results.first?.title == "Notes")
        _ = m.activate(reveal: false)
        #expect(habits.weight("app:/Applications/Notes.app", now: Date()) == 0)
    }

    @Test @MainActor func filesAndWebAndCalcNeverFeedTheHabitStore() async {
        let spy = Spy()
        let (m, habits, _) = make([WebSearchSource()], spy: spy)
        m.query = "x y"
        await m.refresh()
        _ = m.activate(reveal: false)
        #expect(habits.topIDs(limit: 5, now: Date()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: habits.fileURL.path))
    }

    @Test @MainActor func emptyQueryListsHabitItemsAndResetClears() async {
        let spy = Spy()
        let (m, habits, _) = make([StubSource(sourceID: "apps", items: [appItem("Safari"), appItem("Mail")])], spy: spy)
        habits.record("app:/Applications/Mail.app")
        m.query = ""
        await m.refresh()
        #expect(m.results.map(\.title) == ["Mail"])
        m.query = "saf"
        await m.refresh()
        m.reset()
        #expect(m.query.isEmpty && m.results.isEmpty && m.selectedIndex == 0)
    }

    @Test @MainActor func activateWithNoResultDoesNothing() {
        let spy = Spy()
        let (m, _, _) = make([], spy: spy)
        #expect(!m.activate(reveal: false))
    }
}
