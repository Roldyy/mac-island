import Foundation
import IslandTestSupport
import Testing
@testable import DefaultAppsFeature

@MainActor
@Suite struct ModelTests {
    let bench = TestDefaults.make()
    let ls = Fixture.world()

    func model() -> DefaultAppsModel {
        DefaultAppsModel(environment: DefaultAppsEnvironment(launchServices: ls, catalog: FakeCatalog(), defaults: bench.defaults))
    }

    func ready() async -> DefaultAppsModel {
        let m = model()
        m.start()
        await m.refresh()
        m.selectSource(Fixture.textEdit)
        m.selectReplacement(Fixture.sublime)
        await m.settleCandidates()
        return m
    }

    @Test func startingScansNothingAndWritesNothing() {
        defer { bench.cleanup() }
        let m = model()
        m.start()
        #expect(m.isActive && m.phase == .idle && m.scan == .empty && ls.writes.isEmpty)
        #expect(bench.defaults.string(forKey: "defaultAppsJournal") == nil)
    }

    @Test func refreshFillsTheListAndSelectingAnAppShowsItsTypesAndCandidates() async {
        defer { bench.cleanup() }
        let m = await ready()
        #expect(m.phase == .ready && m.replaceable.map(\.id) == [Fixture.textEdit, Fixture.preview])
        #expect(m.source?.count == 6 && m.candidates.map(\.id) == [Fixture.sublime] && m.replacement?.name == "Sublime Text")
    }

    @Test func buildingThePreviewWritesNothingAndAnyChangeOfChoiceDropsIt() async {
        defer { bench.cleanup() }
        let m = await ready()
        m.buildPreview()
        #expect(m.preview?.items.count == 5 && ls.writes.isEmpty)
        m.setMode(.pick)
        #expect(m.preview == nil)
        m.togglePicked("public.json")
        m.buildPreview()
        #expect(m.preview?.items.map(\.identifier) == ["public.json"])
        m.togglePicked("public.rtf")
        #expect(m.preview == nil, "a stale preview can never be confirmed")
        #expect(ls.writes.isEmpty)
    }

    @Test func confirmWithoutAPreviewWritesNothing() async {
        defer { bench.cleanup() }
        let m = await ready()
        await m.confirmAndApply()
        #expect(ls.writes.isEmpty && m.report == nil)
        m.buildPreview()
        m.cancelPreview()
        await m.confirmAndApply()
        #expect(ls.writes.isEmpty)
    }

    @Test func theFullFlowReplacesThenUndoesTheLastReplacementAfterAConfirmation() async {
        defer { bench.cleanup() }
        let m = await ready()
        m.buildPreview()
        await m.confirmAndApply()
        #expect(m.report?.successCount == 5 && m.preview == nil)
        #expect(ls.handlers["public.plain-text"] == Fixture.sublime && ls.handlers["public.folder"] == Fixture.textEdit)
        #expect(m.journalEntries.count == 1 && m.lastEntry?.replacementName == "Sublime Text" && m.storedChoiceCount == 5)
        #expect(m.replaceable.first?.id == Fixture.sublime, "the list is re-read after the write")

        let before = ls.writes.count
        m.requestUndoLast()
        #expect(m.pending == .undoLast && ls.writes.count == before, "asking is not doing")
        await m.confirmPending()
        #expect(ls.handlers["public.plain-text"] == Fixture.textEdit && m.journalEntries.isEmpty && m.pending == nil)
        #expect(m.report?.successCount == 5)
    }

    @Test func restoreAllUndoesEveryEntryAndCancelLeavesEverything() async {
        defer { bench.cleanup() }
        let m = await ready()
        m.buildPreview()
        await m.confirmAndApply()
        m.requestRestoreAll()
        m.cancelPending()
        await m.confirmPending()
        #expect(m.journalEntries.count == 1 && ls.handlers["public.json"] == Fixture.sublime)
        m.requestRestoreAll()
        await m.confirmPending()
        #expect(m.journalEntries.isEmpty && ls.handlers["public.json"] == Fixture.textEdit)
    }

    @Test func aProtectedTypeNeedsItsOwnConfirmationInTheModel() async {
        defer { bench.cleanup() }
        let m = await ready()
        m.setMode(.pick)
        m.togglePicked("public.folder")
        m.buildPreview()
        #expect(m.preview?.items.isEmpty == true && m.preview?.refused.first?.reason == .protectedItem)
        m.setProtectedConfirmed("public.folder", true)
        m.buildPreview()
        #expect(m.preview?.refused.first?.reason == .replacementCannotOpen, "Sublime does not declare folders")
        #expect(ls.writes.isEmpty)
    }

    @Test func aSchemeIsOnlyChangedWhenPickedAndTheSensitiveOnesNeedAConfirmation() async {
        defer { bench.cleanup() }
        let m = await ready()
        m.selectSchemeApp(Fixture.sublime)
        m.selectScheme("http")
        m.buildSchemePreview()
        #expect(m.preview?.items.isEmpty == true && m.preview?.refused.first?.reason == .protectedItem)
        m.setSchemeConfirmed(true)
        m.buildSchemePreview()
        #expect(m.preview?.items.map(\.identifier) == ["http"])
        await m.confirmAndApply()
        #expect(ls.schemeHandlers["http"] == Fixture.sublime && ls.writes.map(\.kind) == [.scheme])
        m.requestUndoLast()
        await m.confirmPending()
        #expect(ls.schemeHandlers["http"] == Fixture.browser)
    }

    @Test func stoppingForgetsTheScreenAndKeepsTheJournal() async {
        defer { bench.cleanup() }
        let m = await ready()
        m.buildPreview()
        await m.confirmAndApply()
        m.stop()
        #expect(!m.isActive && m.scan == .empty && m.preview == nil && m.report == nil && m.selectedSourceID == nil)
        #expect(bench.defaults.string(forKey: "defaultAppsJournal") != nil, "the undo journal outlives the screen")
        await m.confirmAndApply()
        #expect(ls.writes.count == 5, "an inactive feature writes nothing more")
    }

    @Test func startingAgainReadsTheJournalOfAPreviousRun() async {
        defer { bench.cleanup() }
        let first = await ready()
        first.buildPreview()
        await first.confirmAndApply()
        let second = model()
        second.start()
        #expect(second.journalEntries.count == 1 && second.lastEntry?.sourceName == "TextEdit")
    }

    @Test func aCorruptJournalIsAnnouncedAndBlocksNothingElse() {
        defer { bench.cleanup() }
        bench.defaults.set("garbage", forKey: "defaultAppsJournal")
        let m = model()
        m.start()
        #expect(m.journalNotice != nil && m.journalEntries.isEmpty)
    }
}
