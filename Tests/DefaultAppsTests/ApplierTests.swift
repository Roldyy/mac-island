import Foundation
import IslandTestSupport
import Testing
@testable import DefaultAppsFeature

@MainActor
@Suite struct ApplierTests {
    let bench = TestDefaults.make()
    let ls = Fixture.world()
    let catalog = FakeCatalog()

    func parts() -> (applier: DefaultAppsApplier, journal: DefaultAppsJournalStore, choices: DefaultAppsChoicesStore, preview: ReplacementPreview) {
        let journal = DefaultAppsJournalStore(defaults: bench.defaults)
        let choices = DefaultAppsChoicesStore(defaults: bench.defaults)
        let planner = ReplacementPlanner(catalog: catalog)
        let applier = DefaultAppsApplier(launchServices: ls, planner: planner, journal: journal, choices: choices,
                                         now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let scan = DefaultAppsScanner(launchServices: ls, catalog: catalog).scan()
        let preview = planner.preview(source: scan.replaceable.first { $0.id == Fixture.textEdit }!, replacement: scan.app(Fixture.sublime)!,
                                      selection: .all, scan: scan)
        return (applier, journal, choices, preview)
    }

    @Test func noWriteWithoutTheConfirmationOfThatPreview() async {
        defer { bench.cleanup() }
        let p = parts()
        for token in [nil, UUID()] as [UUID?] {
            let report = await p.applier.apply(p.preview, confirmedPreviewID: token)
            #expect(report.outcomes.count == p.preview.items.count && report.successCount == 0)
        }
        #expect(ls.writes.isEmpty && p.journal.entries.isEmpty && p.choices.choices.isEmpty)
    }

    @Test func theJournalIsWrittenBeforeTheFirstChange() async {
        defer { bench.cleanup() }
        let p = parts()
        let seen = Seen()
        let journal = p.journal
        ls.beforeWrite = { _, id in
            // The journal is read on the main actor's behalf from the fake: it only reads defaults.
            let entries = journal.entries
            seen.record(id: id, planned: entries.last?.changes.contains { $0.identifier == id && $0.state == .planned } == true)
        }
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(!seen.first.isEmpty && seen.first.allSatisfy { $0 }, "the first write already finds its planned entry on disk")
        #expect(ls.writes.count == 5)
    }

    @Test func theCallsAreSerialised() async {
        defer { bench.cleanup() }
        let p = parts()
        ls.delay = .milliseconds(5)
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(ls.writes.count == 5 && ls.peak == 1)
    }

    @Test func aSuccessChangesTheDefaultRecordsThePreviousOneAndKeepsTheChoice() async {
        defer { bench.cleanup() }
        let p = parts()
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(report.successCount == 5 && !report.stoppedEarly)
        #expect(ls.handlers["public.json"] == Fixture.sublime && ls.handlers["public.folder"] == Fixture.textEdit)
        let entry = p.journal.entries[0]
        #expect(entry.replacementBundleID == Fixture.sublime && entry.changes.allSatisfy { $0.previousBundleID == Fixture.textEdit && $0.state == .applied })
        #expect(p.choices.choices.count == 5)
    }

    @Test func aPartialFailureIsReportedPerTypeAndNothingIsRetried() async {
        defer { bench.cleanup() }
        let p = parts()
        ls.failing = ["public.json"]
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(report.successCount == 4 && report.failureCount == 1 && !report.stoppedEarly)
        #expect(ls.writes.filter { $0.identifier == "public.json" }.count == 1, "one attempt, no loop")
        #expect(report.outcomes.first { $0.identifier == "public.json" }?.result == .failure("Échec simulé."))
        #expect(p.journal.entries[0].changes.first { $0.identifier == "public.json" }?.state == .failed)
        #expect(!p.choices.choices.contains { $0.identifier == "public.json" })
    }

    @Test func refusingMacOSsSheetStopsTheRestAtOnce() async {
        defer { bench.cleanup() }
        let p = parts()
        let second = p.preview.items[1].identifier
        ls.cancelling = [second]
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(report.stoppedEarly && ls.writes.count == 2)
        #expect(report.outcomes.suffix(3).allSatisfy { $0.result == .skipped("Interrompu.") })
    }

    @Test func threeFailuresInARowStopTheRun() async {
        defer { bench.cleanup() }
        let p = parts()
        ls.failing = Set(p.preview.items.prefix(3).map(\.identifier))
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(report.stoppedEarly && ls.writes.count == 3 && report.failureCount == 3 && report.skippedCount == 2)
    }

    @Test func aWriteMacOSIgnoresIsReportedAsUnverifiedNotSuccess() async {
        defer { bench.cleanup() }
        let p = parts()
        ls.ignoring = ["public.rtf"]
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(report.outcomes.first { $0.identifier == "public.rtf" }?.result == .unverified)
        #expect(p.journal.entries[0].changes.first { $0.identifier == "public.rtf" }?.state == .unverified)
    }

    @Test func aJournalThatCannotBeWrittenMeansNothingIsChanged() async {
        defer { bench.cleanup() }
        let p = parts()
        bench.defaults.set("{\"version\":9,\"entries\":[]}", forKey: DefaultAppsJournalStore.key)
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(ls.writes.isEmpty && report.successCount == 0)
    }

    @Test func aPreviewItemThatBypassedThePlannerIsStillRefusedAtWriteTime() async {
        defer { bench.cleanup() }
        let p = parts()
        let sneaky = [PreviewItem(kind: .contentType, identifier: "public.folder", title: "Dossier", previousBundleID: Fixture.textEdit,
                                  previousName: "TextEdit", isProtected: true, explicitlyPicked: false),
                      PreviewItem(kind: .contentType, identifier: "com.adobe.pdf", title: "PDF", previousBundleID: Fixture.preview,
                                  previousName: "Preview", isProtected: false, explicitlyPicked: false)]
        let preview = ReplacementPreview(sourceName: "TextEdit", replacement: p.preview.replacement, items: sneaky, refused: [])
        let report = await p.applier.apply(preview, confirmedPreviewID: preview.id)
        #expect(ls.writes.isEmpty && report.skippedCount == 2 && p.journal.entries.isEmpty)
    }

    // MARK: undo

    @Test func undoPutsBackThePreviousDefaultsAndEmptiesTheJournal() async {
        defer { bench.cleanup() }
        let p = parts()
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        let report = await p.applier.undo(entries: p.journal.entries)
        #expect(report.successCount == 5)
        #expect(ls.handlers["public.json"] == Fixture.textEdit && ls.handlers["public.plain-text"] == Fixture.textEdit)
        #expect(p.journal.entries.isEmpty && p.choices.choices.isEmpty)
    }

    @Test func undoLeavesWhatTheUserChangedSinceAndKeepsAFailureForALaterTry() async {
        defer { bench.cleanup() }
        let p = parts()
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        ls.handlers["public.json"] = Fixture.preview        // the user picked something else since
        ls.failing = ["public.rtf"]
        let report = await p.applier.undo(entries: p.journal.entries)
        #expect(report.outcomes.first { $0.identifier == "public.json" }?.result == .skipped("Modifié depuis : laissé tel quel."))
        #expect(ls.handlers["public.json"] == Fixture.preview)
        #expect(report.failureCount == 1)
        #expect(p.journal.entries.first?.changes.map(\.identifier) == ["public.rtf"], "only the failure stays in the journal")
    }

    @Test func undoOfOneEntryLeavesTheOlderOnes() async {
        defer { bench.cleanup() }
        let p = parts()
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        let scan = DefaultAppsScanner(launchServices: ls, catalog: catalog).scan()
        let planner = ReplacementPlanner(catalog: catalog)
        let narrow = AppProfile(bundleID: "x.narrow", name: "Narrow", url: URL(fileURLWithPath: "/Applications/Narrow.app"),
                                declared: DeclaredTypes(contentTypes: ["public.json"]))
        ls.install("x.narrow", name: "Narrow", path: "/Applications/Narrow.app")
        let again = planner.preview(source: scan.replaceable.first { $0.id == Fixture.sublime }!, replacement: narrow, selection: .all, scan: scan)
        _ = await p.applier.apply(again, confirmedPreviewID: again.id)
        #expect(p.journal.entries.count == 2 && ls.handlers["public.json"] == "x.narrow")
        _ = await p.applier.undo(entries: [p.journal.entries[1]])
        #expect(ls.handlers["public.json"] == Fixture.sublime && p.journal.entries.count == 1)
        _ = await p.applier.undo(entries: p.journal.entries)
        #expect(ls.handlers["public.json"] == Fixture.textEdit && p.journal.entries.isEmpty)
    }

    @Test func undoWithAnUnknownPreviousOrAMissingAppSkipsSafely() async {
        defer { bench.cleanup() }
        let p = parts()
        let entry = JournalEntry(date: Date(), replacementBundleID: Fixture.sublime, replacementName: "S", sourceName: nil, changes: [
            JournalChange(kind: .contentType, identifier: "public.json", previousBundleID: nil, state: .applied),
            JournalChange(kind: .contentType, identifier: "public.rtf", previousBundleID: "gone.app", state: .applied),
        ])
        ls.handlers["public.json"] = Fixture.sublime
        ls.handlers["public.rtf"] = Fixture.sublime
        p.journal.append(entry)
        let report = await p.applier.undo(entries: [entry])
        #expect(ls.writes.isEmpty)
        #expect(report.outcomes.map(\.result) == [.skipped("Ancien choix inconnu."), .failure("L’application d’origine est introuvable.")])
    }
}

/// Collects what each write found in the journal.
final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func record(id: String, planned: Bool) { lock.lock(); values.append(planned); lock.unlock() }
    var first: [Bool] { lock.lock(); defer { lock.unlock() }; return values }
}
