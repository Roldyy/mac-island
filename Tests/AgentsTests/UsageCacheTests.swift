import Foundation
import Testing
@testable import AgentsFeature

/// The on-disk parse cache, the progressive read (newest files first) and the model that publishes from them.
@Suite struct UsageCacheTests {
    static let calendar = UsageFormat.calendar
    static let now = DateComponents(calendar: calendar, year: 2026, month: 10, day: 31, hour: 15, minute: 20).date ?? Date()

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// `count` files, file `i` last modified `ages[i]` seconds before `now`, each holding `perFile` records
    /// that precede its mtime by a minute. Returns the folder.
    static func makeTree(ages: [TimeInterval], perFile: Int = 3, now: Date = now) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agents-usage-\(UUID().uuidString)")
        let sub = dir.appendingPathComponent("p1")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for (index, age) in ages.enumerated() {
            let mtime = now.addingTimeInterval(-age)
            let lines = (0..<perFile).map { n in
                UsageParsingTests.line(id: "f\(index)-\(n)", ts: iso(mtime.addingTimeInterval(-60 - Double(n))),
                                       input: 100, output: 200, cw: 300, cr: 400)
            }
            let url = sub.appendingPathComponent("s\(index).jsonl")
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        }
        return dir
    }

    static func tempStore() -> UsageCacheStore {
        UsageCacheStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-cache-\(UUID().uuidString)").appendingPathComponent("usage-cache.bin"))
    }

    static func sampleEntries() -> [String: UsageFileCache.Entry] {
        var parse = ClaudeUsageParser.FileParse()
        parse.committedOffset = 1234
        parse.committed.malformedLines = 2
        parse.committed.records = [
            UsageRecord(messageID: "m1", model: "claude-opus-4-5", timestamp: now, inputTokens: 1, outputTokens: 2,
                        cacheCreationTokens: 3, cacheReadTokens: 4, project: "odoo"),
            UsageRecord(messageID: nil, model: "claude-haiku-4-5", timestamp: now.addingTimeInterval(5.25), inputTokens: 10,
                        outputTokens: 20, cacheCreationTokens: 30, cacheReadTokens: 40, project: ""),
        ]
        parse.tail.records = [UsageRecord(messageID: "tail", model: "claude-opus-4-5", timestamp: now, inputTokens: 5,
                                          outputTokens: 5, cacheCreationTokens: 5, cacheReadTokens: 5, project: "odoo")]
        parse.tail.malformedLines = 1
        return ["/logs/a.jsonl": UsageFileCache.Entry(key: .init(size: 99, mtime: now), parse: parse,
                                                       fingerprint: Data([1, 2, 3, 4]))]
    }

    // MARK: codec and store

    @Test func cacheRoundTripsThroughTheCodec() throws {
        let entries = Self.sampleEntries()
        let back = try UsageCacheCodec.decode(UsageCacheCodec.encode(entries))
        let a = try #require(entries["/logs/a.jsonl"]), b = try #require(back["/logs/a.jsonl"])
        #expect(b.key == a.key && b.fingerprint == a.fingerprint)
        #expect(b.parse.committedOffset == 1234)
        #expect(b.parse.committed.records == a.parse.committed.records)
        #expect(b.parse.tail.records == a.parse.tail.records)
        #expect(b.parse.committed.malformedLines == 2 && b.parse.tail.malformedLines == 1)
    }

    @Test func aFractionalModificationDateComesBackBitForBit() throws {
        // File systems report sub-microsecond mtimes; a lossy round trip made every such file look changed.
        let odd = Date(timeIntervalSinceReferenceDate: 783_456_789.123_456_7)
        var entries = Self.sampleEntries()
        entries["/logs/a.jsonl"]?.key.mtime = odd
        let back = try UsageCacheCodec.decode(UsageCacheCodec.encode(entries))
        #expect(back["/logs/a.jsonl"]?.key.mtime == odd)
    }

    @Test func recordsOlderThanTheWindowAreDroppedWhenSaving() throws {
        let back = try UsageCacheCodec.decode(UsageCacheCodec.encode(Self.sampleEntries(), keepingSince: Self.now.addingTimeInterval(1)))
        #expect(back["/logs/a.jsonl"]?.parse.committed.records.count == 1)
        #expect(back["/logs/a.jsonl"]?.parse.tail.records.isEmpty == true)
    }

    @Test func corruptTruncatedAndForeignFilesAreRejected() throws {
        let good = UsageCacheCodec.encode(Self.sampleEntries())
        var flipped = good
        flipped[flipped.count - 3] ^= 0xFF
        #expect(throws: (any Error).self) { try UsageCacheCodec.decode(flipped) }
        #expect(throws: (any Error).self) { try UsageCacheCodec.decode(good.prefix(good.count - 10)) }
        #expect(throws: (any Error).self) { try UsageCacheCodec.decode(Data("not a cache".utf8)) }
        var newer = good
        newer[4] = 99   // another schema version
        #expect(throws: (any Error).self) { try UsageCacheCodec.decode(newer) }
    }

    @Test func storeWritesOwnerOnlyAtomicallyAndDiscardsACorruptFile() throws {
        let store = Self.tempStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        #expect(store.read() == nil)   // missing
        #expect(store.write(Self.sampleEntries(), keepingSince: nil))
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(store.read()?.count == 1)
        #expect(store.write(Self.sampleEntries(), keepingSince: nil))   // replace in place
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path)
        #expect(leftovers == [store.url.lastPathComponent])
        try Data("garbage".utf8).write(to: store.url)
        #expect(store.read() == nil)   // corrupt: discarded, not repaired
    }

    @Test func aCorruptCacheOnDiskJustMeansAFullRead() throws {
        let dir = try Self.makeTree(ages: [60, 120])
        let store = Self.tempStore()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.url)
        let result = ClaudeUsageSource(directory: dir, store: store).load(modifiedSince: nil)
        #expect(result.parsedFileCount == 2 && result.records.count == 6)
        #expect(store.read()?.count == 2)   // and the next save replaced it
    }

    // MARK: source on top of the store

    @Test func aRelaunchStartsWarmAndRereadsOnlyTheChangedFile() throws {
        let dir = try Self.makeTree(ages: [60, 3_600, 7_200])
        let store = Self.tempStore()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let first = ClaudeUsageSource(directory: dir, store: store).load(modifiedSince: nil)
        #expect(first.parsedFileCount == 3)

        // Relaunch, nothing changed: the last known numbers come out before any file is read, then nothing is parsed.
        var early: [UsageProgress] = []
        let second = ClaudeUsageSource(directory: dir, store: store).load(modifiedSince: nil, shouldContinue: { true }) { early.append($0) }
        #expect(early.first?.result.records.count == 9 && early.first?.missingNewest == nil)
        #expect(second.parsedFileCount == 0 && second.records.count == 9)

        // The newest file grows: only that one is read again, and only from where it stopped.
        let newest = dir.appendingPathComponent("p1/s0.jsonl")
        let handle = try FileHandle(forWritingTo: newest)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((UsageParsingTests.line(id: "f0-new", ts: Self.iso(Self.now)) + "\n").utf8))
        try handle.close()
        let source = ClaudeUsageSource(directory: dir, store: store)
        let third = source.load(modifiedSince: nil)
        #expect(third.parsedFileCount == 1 && third.records.count == 10)
        #expect(source.cache.resumeCount == 1)
    }

    @Test func filesAreReadNewestFirstAndEachReportIsAMoreCompletePicture() throws {
        // 2 files today, 2 within the week, 2 within the month (15:20 on the 31st: today starts 15 h 20 min back).
        let day: TimeInterval = 86_400
        let dir = try Self.makeTree(ages: [600, 3_600, 3 * day, 4 * day, 20 * day, 21 * day])
        defer { try? FileManager.default.removeItem(at: dir) }
        var source = ClaudeUsageSource(directory: dir)
        source.workers = 1
        source.reportInterval = 0
        var updates: [UsageUpdate] = []
        UsagePipeline.run(sources: [source], limitSource: PlanLimitSource(url: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")),
                          planLoader: { nil }, now: Self.now, calendar: Self.calendar, shouldContinue: { true },
                          emit: { updates.append($0) })

        #expect(updates.first?.snapshot == nil && updates.first?.coverage == .unread)   // limits only
        #expect(updates.last?.isFinal == true && updates.last?.coverage.isComplete == true)
        let totals = updates.compactMap { $0.snapshot?.summary(for: .month).totalTokens }
        #expect(totals == totals.sorted() && totals.last == 6 * 3 * 1_000)   // never goes backwards, ends complete
        let today = Self.calendar.startOfDay(for: Self.now)
        // After the two newest files: today is complete (and already final), the week and month are not.
        let early = try #require(updates.first { $0.snapshot != nil && $0.coverage.covers(.today, now: Self.now, calendar: Self.calendar)
                                                  && !$0.coverage.covers(.week, now: Self.now, calendar: Self.calendar) })
        let finalToday = try #require(updates.last?.snapshot?.summary(for: .today).totalTokens)
        #expect(early.snapshot?.summary(for: .today).totalTokens == finalToday)
        #expect(finalToday == 2 * 3 * 1_000 && UsagePeriod.today.interval(now: Self.now, calendar: Self.calendar).start == today)
        let weekComplete = try #require(updates.first { $0.coverage.covers(.week, now: Self.now, calendar: Self.calendar)
                                                         && !$0.coverage.covers(.month, now: Self.now, calendar: Self.calendar) })
        #expect(weekComplete.snapshot?.summary(for: .week).totalTokens == 4 * 3 * 1_000)
    }

    @Test func coverageSaysWhichPeriodsAreComplete() {
        let c = Self.calendar
        let missing = UsageCoverage(missingNewest: Self.now.addingTimeInterval(-2 * 86_400))
        #expect(missing.covers(.today, now: Self.now, calendar: c))
        #expect(!missing.covers(.week, now: Self.now, calendar: c))
        #expect(UsageCoverage.complete.covers(.month, now: Self.now, calendar: c))
        #expect(!UsageCoverage.unread.covers(.today, now: Self.now, calendar: c))
    }

    // MARK: model

    @MainActor static func model(_ source: ClaudeUsageSource) -> AgentsUsageModel {
        AgentsUsageModel(settings: AgentsSettings(store: WindowTests.FakeStore()), sources: [source],
                         limitSource: PlanLimitSource(url: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")),
                         planLoader: { nil }, calendar: calendar, clock: { now }, sessionProbe: { false })
    }

    @MainActor @Test func theFirstSnapshotComesFromTheDiskCacheBeforeAnyFileIsRead() async throws {
        let dir = try Self.makeTree(ages: Array((0..<150).map { TimeInterval($0) * 3_600 }), perFile: 120)
        let store = Self.tempStore()
        defer { try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let cold = Self.model(ClaudeUsageSource(directory: dir, store: store))
        await cold.refresh()
        #expect(cold.hasLoaded && cold.coverage.isComplete && cold.status == .ready)
        let expected = cold.snapshot

        let warm = Self.model(ClaudeUsageSource(directory: dir, store: store))   // a relaunch: empty memory, cache on disk
        let started = Date()
        let task = Task { await warm.refresh() }
        while !warm.hasLoaded { try await Task.sleep(for: .milliseconds(1)) }
        let firstPaint = Date().timeIntervalSince(started)
        await task.value
        print("MIS_CACHE firstPaint=\(Int(firstPaint * 1000)) ms records=\(150 * 120)")
        #expect(warm.snapshot == expected)
        // Debug builds are several times slower than release (the shipped one); the bar is 50 ms there.
        #if DEBUG
        #expect(firstPaint < 0.5)
        #else
        #expect(firstPaint < 0.05)
        #endif
    }

    @MainActor @Test func closingThePageStopsAReadItStartedButNotTheWarmUps() async throws {
        let dir = try Self.makeTree(ages: Array((0..<40).map { TimeInterval($0) * 600 }), perFile: 50)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = Self.model(ClaudeUsageSource(directory: dir))
        model.pageDidAppear()
        let task = Task { await model.refresh(interactive: true) }
        model.pageDidDisappear()   // closed straight away: the read is cancelled, whatever finished stays cached
        await task.value
        #expect(!model.isRefreshing)
        await model.refresh()      // and the next one simply finishes the job
        #expect(model.coverage.isComplete && model.hasLoaded)
    }
}
