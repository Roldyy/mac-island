import Foundation
import IslandTestSupport
import Testing
@testable import DefaultAppsFeature

/// The defects of the first review: stale scan, guard racing apply/undo, timeouts, hostile plists, lying previews.
@MainActor
@Suite struct HardeningTests {
    let bench = TestDefaults.make()
    let ls = Fixture.world()
    let catalog = FakeCatalog()

    struct Parts {
        let applier: DefaultAppsApplier
        let journal: DefaultAppsJournalStore
        let choices: DefaultAppsChoicesStore
        let preview: ReplacementPreview
        let gate: DefaultAppsWriteGate
    }

    func parts(shouldContinue: @escaping @MainActor () -> Bool = { true }) -> Parts {
        let journal = DefaultAppsJournalStore(defaults: bench.defaults)
        let choices = DefaultAppsChoicesStore(defaults: bench.defaults)
        let planner = ReplacementPlanner(catalog: catalog)
        let gate = DefaultAppsWriteGate()
        let applier = DefaultAppsApplier(launchServices: ls, planner: planner, journal: journal, choices: choices,
                                         now: { Date(timeIntervalSince1970: 1_800_000_000) }, gate: gate, shouldContinue: shouldContinue)
        let scan = DefaultAppsScanner(launchServices: ls, catalog: catalog).scan()
        let preview = planner.preview(source: scan.replaceable.first { $0.id == Fixture.textEdit }!, replacement: scan.app(Fixture.sublime)!,
                                      selection: .all, scan: scan)
        return Parts(applier: applier, journal: journal, choices: choices, preview: preview, gate: gate)
    }

    // MARK: 1 stale scan

    @Test func aTypeWhoseHandlerChangedSinceThePreviewIsSkippedAndNotJournaled() async {
        defer { bench.cleanup() }
        let p = parts()
        ls.handlers["public.json"] = Fixture.preview           // changed after the scan, before the click
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(report.outcomes.first { $0.identifier == "public.json" }?.result == .skipped("A changé depuis l’aperçu : relancez l’aperçu."))
        #expect(!ls.writes.contains { $0.identifier == "public.json" } && ls.handlers["public.json"] == Fixture.preview)
        #expect(report.successCount == 4)
        #expect(p.journal.entries[0].changes.count == 4 && !p.journal.entries[0].changes.contains { $0.identifier == "public.json" })
        #expect(p.journal.entries[0].changes.allSatisfy { $0.previousBundleID == Fixture.textEdit }, "the recorded handler is the live one")
    }

    @Test func ifEveryHandlerChangedNothingIsWrittenAndNoEntryIsCreated() async {
        defer { bench.cleanup() }
        let p = parts()
        for item in p.preview.items { ls.handlers[item.identifier] = Fixture.preview }
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(ls.writes.isEmpty && report.skippedCount == 5 && p.journal.entries.isEmpty && p.choices.choices.isEmpty)
    }

    // MARK: 4 lying protection flag

    @Test func theApplierAsksThePolicyItselfWhateverThePreviewItemClaims() async {
        defer { bench.cleanup() }
        let p = parts()
        let liar = { (kind: ChangeKind, id: String, from: String?) in
            PreviewItem(kind: kind, identifier: id, title: id, previousBundleID: from, previousName: nil, isProtected: false, explicitlyPicked: false)
        }
        let items = [liar(.contentType, "public.folder", Fixture.textEdit), liar(.scheme, "http", Fixture.browser), liar(.scheme, "mailto", nil)]
        let preview = ReplacementPreview(sourceName: nil, replacement: p.preview.replacement, items: items, refused: [])
        let report = await p.applier.apply(preview, confirmedPreviewID: preview.id)
        #expect(ls.writes.isEmpty && p.journal.entries.isEmpty)
        #expect(report.outcomes.map(\.result) == Array(repeating: .skipped(RefusalReason.protectedItem.text), count: 3))
    }

    @Test func aProtectedItemExplicitlyPickedStillGoesThrough() async {
        defer { bench.cleanup() }
        let p = parts()
        let item = PreviewItem(kind: .scheme, identifier: "http", title: "Liens http:", previousBundleID: Fixture.browser, previousName: nil,
                               isProtected: false, explicitlyPicked: true)
        let preview = ReplacementPreview(sourceName: nil, replacement: p.preview.replacement, items: [item], refused: [])
        let report = await p.applier.apply(preview, confirmedPreviewID: preview.id)
        #expect(report.successCount == 1 && ls.schemeHandlers["http"] == Fixture.sublime)
        #expect(p.choices.choices.first?.explicitlyPicked == true, "the guard may re-apply only what was picked on purpose")
    }

    // MARK: 3 timeout then late answer

    @Test func aTimeoutIsUnknownNotFailedStopsTheRunAndTheLateAnswerStaysUndoable() async {
        defer { bench.cleanup() }
        let p = parts()
        let second = p.preview.items[1].identifier
        ls.timingOut = [second]
        let report = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        #expect(report.stoppedEarly && ls.writes.count == 2, "nothing is queued behind a pending macOS call")
        #expect(report.outcomes[1].result == .unverified)
        #expect(report.outcomes.suffix(3).allSatisfy { $0.result == .skipped("Interrompu.") })
        let states = Dictionary(uniqueKeysWithValues: p.journal.entries[0].changes.map { ($0.identifier, $0.state) })
        #expect(states[second] == .planned, "unknown: never marked failed")
        #expect(!p.choices.choices.contains { $0.identifier == second })
        #expect(ls.handlers[second] == Fixture.sublime, "the late answer landed")

        ls.timingOut = []
        let undo = await p.applier.undo(entries: p.journal.entries)
        #expect(ls.handlers[second] == Fixture.textEdit && ls.handlers[p.preview.items[0].identifier] == Fixture.textEdit)
        #expect(undo.outcomes.first { $0.identifier == second }?.result == .success)
        #expect(p.journal.entries.isEmpty)
    }

    @Test func aTimeoutDuringAnUndoKeepsTheItemInTheJournal() async {
        defer { bench.cleanup() }
        let p = parts()
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        let victim = p.preview.items[0].identifier
        ls.timingOut = [victim]
        let report = await p.applier.undo(entries: p.journal.entries)
        #expect(report.stoppedEarly && report.outcomes[0].result.isFailure)
        #expect(p.journal.entries.first?.changes.count == 5, "the interrupted and the timed-out ones are all still there")
    }

    // MARK: 2 guard and apply / undo together

    @Test func aGuardPassNeverRunsInTheMiddleOfAnUndoAndTheUndoRecordSurvives() async throws {
        defer { bench.cleanup() }
        let p = parts()
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        let settings = DefaultAppsSettings(defaults: bench.defaults)
        settings.guardEnabled = true
        let keeper = DefaultAppsGuard(settings: settings, choices: p.choices, launchServices: ls, gate: p.gate)
        ls.delay = .milliseconds(15)
        let applier = p.applier, entries = p.journal.entries
        let undo = Task { await applier.undo(entries: entries) }
        while ls.writes.count < 6 { try await Task.sleep(for: .milliseconds(2)) }   // the undo is writing (the apply wrote 5)
        let actions = await keeper.check(reason: "during undo")
        let report = await undo.value
        #expect(ls.peak == 1, "one LaunchServices writer at a time")
        #expect(actions.isEmpty, "the undo removed each choice before restoring it: nothing is left to re-apply")
        #expect(report.successCount == 5 && ls.writes.count == 10)
        #expect(ls.handlers["public.json"] == Fixture.textEdit && p.journal.entries.isEmpty && p.choices.choices.isEmpty)
    }

    @Test func eachChoiceIsRemovedBeforeItsTypeIsRestored() async {
        defer { bench.cleanup() }
        let p = parts()
        _ = await p.applier.apply(p.preview, confirmedPreviewID: p.preview.id)
        let seen = Seen()
        let choices = p.choices
        let start = ls.writes.count
        ls.beforeWrite = { _, id in seen.record(id: id, planned: choices.choices.contains { $0.identifier == id }) }
        _ = await p.applier.undo(entries: p.journal.entries)
        #expect(ls.writes.count - start == 5 && seen.first.count == 5 && seen.first.allSatisfy { !$0 })
    }

    @Test func aGuardThatIsNotAllowedDoesNothingEvenWithAResetChoice() async {
        defer { bench.cleanup() }
        let settings = DefaultAppsSettings(defaults: bench.defaults)
        settings.guardEnabled = true
        let choices = DefaultAppsChoicesStore(defaults: bench.defaults)
        choices.upsert(StoredChoice(kind: .contentType, identifier: "public.json", bundleID: Fixture.sublime, explicitlyPicked: false))
        let keeper = DefaultAppsGuard(settings: settings, choices: choices, launchServices: ls, allowed: { false })
        #expect(await keeper.check(reason: "off").isEmpty && ls.writes.isEmpty)
    }

    @Test func theModelSkipsTheGuardWhileAnApplyRunsSoWritesNeverOverlap() async throws {
        defer { bench.cleanup() }
        let m = DefaultAppsModel(environment: DefaultAppsEnvironment(launchServices: ls, catalog: catalog, defaults: bench.defaults))
        m.start()
        await m.refresh()
        m.selectSource(Fixture.textEdit)
        m.selectReplacement(Fixture.sublime)
        m.buildPreview()
        ls.delay = .milliseconds(10)
        let apply = Task { await m.confirmAndApply() }
        while !m.isApplying { try await Task.sleep(for: .milliseconds(1)) }
        m.setGuard(true)                       // asks for a guard pass while the apply owns the writes
        await apply.value
        #expect(ls.peak == 1 && ls.writes.count == 5)
    }

    // MARK: 7 nothing writes after the kill switch

    @Test func stoppingMidApplyWritesNothingMoreAndShowsNothing() async throws {
        defer { bench.cleanup() }
        let m = DefaultAppsModel(environment: DefaultAppsEnvironment(launchServices: ls, catalog: catalog, defaults: bench.defaults))
        m.start()
        await m.refresh()
        m.selectSource(Fixture.textEdit)
        m.selectReplacement(Fixture.sublime)
        m.buildPreview()
        ls.delay = .milliseconds(20)
        let apply = Task { await m.confirmAndApply() }
        while ls.writes.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
        m.stop()
        await apply.value
        let count = ls.writes.count
        try await Task.sleep(for: .milliseconds(80))
        #expect(count < 5 && ls.writes.count == count && m.report == nil && !m.isActive)
        #expect(m.journalEntries.isEmpty || bench.defaults.string(forKey: "defaultAppsJournal") != nil, "the journal stays on disk for the undo")
    }

    // MARK: 6 hostile plists

    @Test func oneEntryWithAHundredThousandTypesIsCappedBeforeItAccumulates() {
        let ids = (0..<100_000).map { "x.type\($0)" }
        let declared = DeclaredTypesExtractor.extract(from: ["CFBundleDocumentTypes": [["LSItemContentTypes": ids]]], catalog: catalog)
        #expect(declared.contentTypes.count == DeclaredTypesExtractor.maxTypesPerEntry)
        let exts = (0..<100_000).map { "e\($0)" }
        #expect(DeclaredTypesExtractor.extract(from: ["CFBundleDocumentTypes": [["CFBundleTypeExtensions": exts]]], catalog: CountingCatalog()).contentTypes.isEmpty)
    }

    @Test func manyFullEntriesStopAtTheTotalCap() {
        let entries = (0..<500).map { e in ["LSItemContentTypes": (0..<100).map { "x.e\(e).t\($0)" }] }
        let declared = DeclaredTypesExtractor.extract(from: ["CFBundleDocumentTypes": entries], catalog: catalog)
        #expect(declared.contentTypes.count == DeclaredTypesExtractor.maxTypes)
    }

    @Test func urlSchemesAreCappedPerEntryAndInTotal() {
        let one = DeclaredTypesExtractor.extract(from: ["CFBundleURLTypes": [["CFBundleURLSchemes": (0..<100_000).map { "s\($0)" }]]], catalog: catalog)
        #expect(one.schemes.count == DeclaredTypesExtractor.maxSchemesPerEntry)
        let entries = (0..<500).map { e in ["CFBundleURLSchemes": (0..<20).map { "s\(e)x\($0)" }] }
        let many = DeclaredTypesExtractor.extract(from: ["CFBundleURLTypes": entries], catalog: catalog)
        #expect(many.schemes.count == DeclaredTypesExtractor.maxSchemes)
    }

    @Test func extensionLookupsHaveABudget() {
        let counting = CountingCatalog()
        let entries = (0..<500).map { _ in ["CFBundleTypeExtensions": (0..<300).map { "z\($0)" }] }
        _ = DeclaredTypesExtractor.extract(from: ["CFBundleDocumentTypes": entries], catalog: counting)
        #expect(counting.lookups <= DeclaredTypesExtractor.maxLookups)
    }

    // MARK: 5 originals through the applier

    @Test func restoreAllReachesTheTrueOriginalEvenWhenTheOlderEntryIsGone() async {
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
        p.journal.replaceEntries([p.journal.entries[1]])         // the older entry is no longer there
        let plain = UndoPlanner.plan(entries: p.journal.entries)
        #expect(plain.first?.restoreTo == Fixture.sublime, "the entry alone only knows the middle handler")
        let report = await p.applier.undo(entries: p.journal.entries, restoringOriginals: true)
        #expect(report.successCount == 1 && ls.handlers["public.json"] == Fixture.textEdit)
    }

    // MARK: 8 memoized conformance, 9 settings

    @Test func conformanceIsAskedOncePerPairNoMatterHowOftenTheListIsBuilt() {
        let counting = CountingCatalog(conformsTo: ["net.daringfireball.markdown": "public.text"])
        let planner = ReplacementPlanner(catalog: counting)
        let sublime = AppProfile(bundleID: "s", name: "S", url: URL(fileURLWithPath: "/Applications/S.app"),
                                 declared: DeclaredTypes(contentTypes: ["public.text"]))
        for _ in 0..<50 { #expect(planner.canOpen(sublime, contentType: "net.daringfireball.markdown")) }
        #expect(counting.conformsCalls == 1)
    }

    @Test func candidatesArePublishedOnceTheSourceIsSelectedAndClearedWithIt() async {
        defer { bench.cleanup() }
        let m = DefaultAppsModel(environment: DefaultAppsEnvironment(launchServices: ls, catalog: catalog, defaults: bench.defaults))
        m.start()
        await m.refresh()
        #expect(m.candidates.isEmpty)
        m.selectSource(Fixture.textEdit)
        await m.settleCandidates()
        #expect(m.candidates.map(\.id) == [Fixture.sublime])
        m.selectSource(nil)
        #expect(m.candidates.isEmpty)
    }
}

/// Counts what the extractor and the planner ask the catalog.
final class CountingCatalog: ContentTypeCataloging, @unchecked Sendable {
    private let lock = NSLock()
    private var _lookups = 0
    private var _conforms = 0
    private let conformsTo: [String: String]

    init(conformsTo: [String: String] = [:]) { self.conformsTo = conformsTo }

    var lookups: Int { lock.lock(); defer { lock.unlock() }; return _lookups }
    var conformsCalls: Int { lock.lock(); defer { lock.unlock() }; return _conforms }

    func identifier(forExtension ext: String) -> String? { lock.lock(); _lookups += 1; lock.unlock(); return nil }
    func extensions(forIdentifier id: String) -> [String] { [] }
    func description(forIdentifier id: String) -> String? { nil }
    func conforms(_ id: String, to parent: String) -> Bool {
        lock.lock(); _conforms += 1; lock.unlock()
        return id == parent || conformsTo[id] == parent
    }
}
